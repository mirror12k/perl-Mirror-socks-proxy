#!/usr/bin/env perl
package Mirror::Reflective;
use strict;
use warnings;

use feature 'say';

use IO::Select;
use Iron::TCP;
use IO::Socket::INET;



sub new {
	my ($class, %args) = @_;
	my $self = bless {}, $class;

	$self->{port} = $args{port} // 3210;


	return $self
}

sub start {
	my ($self) = @_;

	$self->{server_socket} = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalPort => $self->{port},
		Listen => SOMAXCONN,
		Reuse => 1,
		# Blocking => 1,
	) or die "ERROR: failed to set up listening socket: $!";

	$self->{socket_data} = {};

	$self->{running} = 1;


	$self->{selector} = IO::Select->new($self->{server_socket});
	while ($self->{running}) {
		say "this loop";
		# say "this loop with handles (server socket: $self->{server_socket}): ", $self->{selector}->handles;
		while (my @ready = $self->{selector}->can_read) {
			say "ready: @ready";
			foreach my $socket (@ready) {
				if ($socket == $self->{server_socket}) {
					my $new_socket = $socket->accept;
					$self->new_socket($new_socket, is_client_connection => 1);
				} elsif (eof $socket) {
					$self->disconnect_socket($socket);
				} else {
					$self->on_data($socket);
				}
			}
			# say "end ready with handles: ", $self->{selector}->handles;
		}
		# say "end loop with exceptions: ", $self->{selector}->has_exception(0);
		sleep 1;
	}
}

sub new_socket {
	my ($self, $socket, %args) = @_;

	$socket->blocking(0);
	$self->{socket_data}{"$socket"} = { %args };
	$self->on_connect($socket, %args);
	$self->{selector}->add($socket);
}

sub disconnect_socket {
	my ($self, $socket) = @_;
	say "disconnecting socket $socket";

	$self->on_disconnect($socket);
	$self->{selector}->remove($socket);
	# NOTE FOR FUTURE: closing the socket before removing it from the selector will result in a glitched and broken selector
	$socket->close;
	delete $self->{socket_data}{"$socket"};
}

sub on_connect {
	my ($self, $socket, %args) = @_;
	my $data = $self->{socket_data}{"$socket"};

	my $peer_ip = join '.', map ord, split '', $socket->peeraddr;
	my $peer_port = $socket->peerport;

	$data->{buffer} = '';
	if ($data->{is_client_connection}) {
		say "new client $peer_ip:$peer_port";
		$data->{is_handshake_complete} = 0;
	} else {
		say "new service to $peer_ip:$peer_port";
	}
}

sub on_data {
	my ($self, $socket) = @_;
	my $data = $self->{socket_data}{"$socket"};

	my $len;
	do {
		$len = read $socket, $data->{buffer}, 4096, length $data->{buffer};
		say "got data from $socket" if $len;
		# say "got data from $socket: ", unpack 'H*', $buffer if $len;
	} while ($len);

	warn "nothing read" unless length $data->{buffer};

	if (defined $data->{paired_socket}) {
		$data->{paired_socket}->send($data->{buffer});
		$data->{buffer} = '';
	} elsif ($data->{is_client_connection} and $data->{buffer} =~ /\A(.)(.)(.{2})(.{4})([^\0]*\0)/s) {
		my ($socks_version, $command_code, $port, $ip) = ($1, $2, $3, $4);
		$socks_version = ord $socks_version;
		$command_code = ord $command_code;
		$ip = join '.', map ord, split '', $ip;
		$port = unpack 'n', $port;

		return $self->disconnect_socket($socket) unless $socks_version == 4;
		return $self->disconnect_socket($socket) unless $command_code == 1;

		my $hostport;
		if ($ip eq '0.0.0.1') {
			if ($data->{buffer} =~ /\A(.)(.)(.{2})(.{4})([^\0]*\0)([^\0]*)\0/) {
				$hostport = "$6:$port";
				$data->{buffer} = $';
				$data->{is_socks4a_connection} = 1;
			} else {
				warn "invalid socks4a message from $socket";
				return $self->disconnect_socket($socket);
			}
		} else {
			$hostport = "$ip:$port";
			$data->{buffer} = $';
		}

		my $connection = Iron::TCP->new(hostport => $hostport);
		if ($connection and $connection->connected) {
			say "socks connected $hostport";
			$socket->send("\0\x5a\0\0\0\0\0\0");
			$data->{is_handshake_complete} = 1;
			$data->{paired_socket} = $connection->{sock};

			$self->new_socket($connection->{sock}, is_service_connection => 1, paired_socket => $socket);

			# tail call on_data if the client sent more data than just the header
			if (length $data->{buffer}) {
				say "looping ondata";
				$self->on_data($socket);
			}
		} else {
			$socket->send("\0\x5b\0\0\0\0\0\0");
			return $self->disconnect_socket($socket);
		}
	} else {
		warn "invalid message from $socket";
		return $self->disconnect_socket($socket);
	}
}

sub on_disconnect {
	my ($self, $socket) = @_;
	my $data = $self->{socket_data}{"$socket"};
	say "dead socket $socket";

	if (defined $data->{paired_socket}) {
		say "disconnecting paired socket";
		my $other_socket = $data->{paired_socket};
		delete $self->{socket_data}{"$data->{paired_socket}"}{paired_socket};
		delete $data->{paired_socket};
		$self->disconnect_socket($other_socket);
	}
}


sub main {
	Mirror::Reflective->new->start
}

caller or main(@ARGV);
