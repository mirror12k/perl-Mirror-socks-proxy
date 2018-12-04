package Mirror::Enchanted::ClientConnection;
use parent 'Mirror::PairedConnection';
use strict;
use warnings;

use feature 'say';

use Iron::TCP;
use IO::Socket::SSL;
use Iron::SSL;
use HTTP::Request;

use Mirror::Enchanted::ServiceConnection;



sub new {
	my ($class, $socket, %args) = @_;
	my $self = $class->SUPER::new($socket, is_header => 1, %args);
	return $self
}

sub on_data {
	my ($self, $mir) = @_;

	if ($self->{is_handshake_complete}) {
		# HTTP::Request parsing code
		if ($self->{is_header}) { # receive header
			if ($self->{buffer} =~ /\r?\n\r?\n/s) {
				$self->{buffer} = $';
				my $req = HTTP::Request->parse("$`\r\n\r\n");

				if (defined $req->header('Content-Length') and 0 < int $req->header('Content-Length')) {
					$self->{is_header} = 0;
					$self->{content_length} = int $req->header('Content-Length');
					$self->{request} = $req;

					$self->on_data($mir) if length $self->{buffer};
				} else {
					$self->on_request($mir, $req);
				}
			}
		} else { #receive body
			if (length $self->{buffer} >= $self->{content_length}) {
				$self->{request}->content(substr $self->{buffer}, 0, $self->{content_length});
				$self->{buffer} = substr $self->{buffer}, $self->{content_length};
				$self->{is_header} = 1;

				$self->on_request($mir, $self->{request});
			}
		}

	} elsif ($self->{buffer} =~ /\A(.)(.)(.{2})(.{4})([^\0]*\0)/s) {
		#socks4/4a handshake code
		my ($socks_version, $command_code, $port, $ip) = ($1, $2, $3, $4);
		$socks_version = ord $socks_version;
		$command_code = ord $command_code;
		$ip = join '.', map ord, split '', $ip;
		$port = unpack 'n', $port;

		return $mir->disconnect_connection($self) unless $socks_version == 4;
		return $mir->disconnect_connection($self) unless $command_code == 1;

		my $request_hostport;
		if ($ip eq '0.0.0.1') {
			if ($self->{buffer} =~ /\A(.)(.)(.{2})(.{4})([^\0]*\0)([^\0]*)\0/) {
				$request_hostport = "$6:$port";
				$self->{buffer} = $';
				$self->{is_socks4a_connection} = 1;
			} else {
				warn "invalid socks4a message from $self->{peer_address}";
				return $mir->disconnect_connection($self);
			}
		} else {
			$request_hostport = "$ip:$port";
			$self->{buffer} = $';
		}

		if ($request_hostport =~ /:443\Z/) {
			$self->{is_ssl} = 1;
		}

		$self->{requested_connection_hostport} = $request_hostport;

		my $hostport = $mir->on_socks4_handshake($self, $request_hostport);
		$self->{real_connection_hostport} = $hostport;

		if (defined $hostport) {
			$self->{socks_hostport} = $hostport;

			my $connection;
			# TODO: peek the socket and promote it to SSL only after we have established it to be SSL
			if ($self->{is_ssl}) {
				$connection = Iron::SSL->new(hostport => $hostport);
			} else {
				$connection = Iron::TCP->new(hostport => $hostport);
			}

			if ($connection and $connection->connected) {
				# say "socks connected $hostport";
				$self->print("\0\x5a\0\0\0\0\0\0");
				$self->{is_handshake_complete} = 1;
				$self->{paired_connection} = Mirror::Enchanted::ServiceConnection->new($connection->{sock}, paired_connection => $self);

				$mir->new_connection($self->{paired_connection});
			} else {
				$self->print("\0\x5b\0\0\0\0\0\0");
				return $mir->disconnect_connection($self);
			}
		} else {
			# warn "creating a mock-connection for $request_hostport";
			$self->print("\0\x5a\0\0\0\0\0\0");
			$self->{is_handshake_complete} = 1;
		}

		if ($self->{is_ssl}) {
			my ($host) = split ':', $request_hostport;
			# say "upgrading to ssl on $self->{socket}";
			my $old_socket = $self->{socket};
			my $new_socket = IO::Socket::SSL->start_SSL($self->{socket},
				SSL_server => 1,
				SSL_cert_file => $mir->{cert_factory}->certificate($host),
				SSL_key_file => $mir->{cert_factory}{certificate_key},
				Blocking => 0,
			);
			warn "failed to ssl handshake insock: $!, $SSL_ERROR" unless $new_socket;
			return $mir->disconnect_connection($self) unless $new_socket;
			# say "upgraded to ssl on $self->{socket}";
			$self->{socket} = $new_socket;

			$mir->update_connection_socket($old_socket, $self);
		}

		# tail call on_data if the client sent more data than just the header
		if (length $self->{buffer}) {
			# say "looping ondata";
			$self->on_data($mir);
		}
	} else {
		warn "invalid client handshake from $self->{peer_address}";
		return $mir->disconnect_connection($self);
	}

	$self->{buffer} = '';
}

sub on_request {
	my ($self, $mir, $req) = @_;
	my $res = $mir->on_request($self, $req);

	if (defined $res) {
		# if the callback event produced an HTTP::Response object, immediately print that out
		$self->print($res->as_string("\r\n"));
	} else {
		# otherwise patch it to the peer
		$self->{paired_connection}{request} = $req;
		$self->{paired_connection}->print($req->as_string("\r\n"));
	}
}

1;
