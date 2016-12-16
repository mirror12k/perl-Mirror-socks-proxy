package Mirror::Enchanted::ClientConnection;
use strict;
use warnings;

use feature 'say';

use IO::Select;
use Iron::TCP;
use IO::Socket::SSL;
use Iron::SSL;
use HTTP::Request;

use Mirror::Enchanted::ServiceConnection;



sub new {
	my ($class, $socket, %args) = @_;
	my $self = bless { buffer => '', socket => $socket, is_header => 1, %args }, $class;
	return $self
}

sub on_connect {
	my ($self, $mir) = @_;
	say "new " . ref ($self) . " connection $self->{peer_address} ($self->{socket})";
}

sub on_data {
	my ($self, $mir) = @_;

	if ($self->{is_handshake_complete}) {
		if ($self->{is_header}) {
			if ($self->{buffer} =~ /\r?\n\r?\n/s) {
				$self->{buffer} = $';
				my $req = HTTP::Request->parse("$`\r\n\r\n");

				if (defined $req->header('Content-Length') and 0 < int $req->header('Content-Length')) {
					$self->{is_header} = 0;
					$self->{content_length} = int $req->header('Content-Length');
					$self->{request} = $req;
				} else {
					$self->on_request($mir, $req);
				}
			}
		} else {
			if (length $self->{buffer} >= $self->{content_length}) {
				$self->{request}->content(substr $self->{buffer}, 0, $self->{content_length});
				$self->{buffer} = substr $self->{buffer}, $self->{content_length};
				$self->{is_header} = 1;

				$mir->on_request($mir, $self->{request});
				# warn "may have just got a sigpipe" unless $self->{paired_connection}{socket}->print($self->{request}->as_string);
			}
		}

	} elsif ($self->{buffer} =~ /\A(.)(.)(.{2})(.{4})([^\0]*\0)/s) {
		my ($socks_version, $command_code, $port, $ip) = ($1, $2, $3, $4);
		$socks_version = ord $socks_version;
		$command_code = ord $command_code;
		$ip = join '.', map ord, split '', $ip;
		$port = unpack 'n', $port;

		return $mir->disconnect_connection($self) unless $socks_version == 4;
		return $mir->disconnect_connection($self) unless $command_code == 1;

		my $host;
		if ($ip eq '0.0.0.1') {
			if ($self->{buffer} =~ /\A(.)(.)(.{2})(.{4})([^\0]*\0)([^\0]*)\0/) {
				$host = "$6";
				$self->{buffer} = $';
				$self->{is_socks4a_connection} = 1;
			} else {
				warn "invalid socks4a message from $self->{peer_address}";
				return $mir->disconnect_connection($self);
			}
		} else {
			$host = "$ip";
			$self->{buffer} = $';
		}

		my $hostport = "$host:$port";

		my $connection;
		if ($port == 443) {
			$self->{is_ssl} = 1;
			$connection = Iron::SSL->new(hostport => $hostport);
		} else {
			$connection = Iron::TCP->new(hostport => $hostport);
		}

		if ($connection and $connection->connected) {
			say "socks connected $hostport";
			$self->{socket}->print("\0\x5a\0\0\0\0\0\0");
			$self->{is_handshake_complete} = 1;
			$self->{paired_connection} = Mirror::Enchanted::ServiceConnection->new($connection->{sock}, paired_connection => $self);

			$mir->new_connection($self->{paired_connection});

			if ($self->{is_ssl}) {
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
				say "looping ondata";
				$mir->on_data($self->{socket});
			}
		} else {
			$self->{socket}->print("\0\x5b\0\0\0\0\0\0");
			return $mir->disconnect_connection($self);
		}
	} else {
		warn "invalid client handshake from $self->{peer_address}";
		return $mir->disconnect_connection($self);
	}

	$self->{buffer} = '';
}

sub on_disconnect {
	my ($self, $mir) = @_;
	say "disconnected " . ref ($self) . " connection $self->{peer_address} ($self->{socket})";
	# say "disconnected client $self->{peer_address}";

	if (defined $self->{paired_connection}) {
		# say "disconnecting paired connection";
		my $paired_connection = $self->{paired_connection};
		delete $self->{paired_connection}{paired_connection};
		delete $self->{paired_connection};
		$mir->disconnect_connection($paired_connection) if $paired_connection->{socket}->connected;
	}
}

sub on_request {
	my ($self, $mir, $req) = @_;
	my $res = $mir->on_request($self, $req);

	if (defined $res) {
		warn "may have just got a sigpipe" unless $self->{socket}->print($res->as_string);
	} else {
		warn "may have just got a sigpipe" unless $self->{paired_connection}{socket}->print($req->as_string);
	}
}

1;
