#!/usr/bin/env perl
package Mirror::Reflective;
use strict;
use warnings;

use feature 'say';

use IO::Select;
use Iron::TCP;
use IO::Socket::INET;

use Mirror::Reflective::ServiceConnection;
use Mirror::Reflective::ClientConnection;


$| = 1;


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
		while (my @ready = $self->{selector}->can_read) {
			# say "ready: @ready";
			foreach my $socket (@ready) {
				if ($socket == $self->{server_socket}) {
					# say "processing new socket on $socket";
					my $new_socket = $socket->accept;
					$self->new_socket($new_socket);
				} elsif (not $socket->connected) {
					# say "processing death $socket";
					$self->disconnect_socket($socket);
				} else {
					# say "processing data $socket";
					$self->on_data($socket);
				}
			}
		}
	}
}

sub new_socket {
	my ($self, $socket) = @_;
	$self->new_connection(Mirror::Reflective::ClientConnection->new($socket));
}

sub new_connection {
	my ($self, $connection) = @_;

	$connection->{socket}->blocking(0);

	my $peer_ip = join '.', map ord, split '', $connection->{socket}->peeraddr;
	my $peer_port = $connection->{socket}->peerport;
	$connection->{peer_address} = "$peer_ip:$peer_port";

	$self->{socket_data}{"$connection->{socket}"} = $connection;
	$connection->on_connect($self);

	$self->{selector}->add($connection->{socket});
}

sub update_connection_socket {
	my ($self, $old_socket, $connection) = @_;
	delete $self->{socket_data}{"$old_socket"};
	$self->{socket_data}{"$connection->{socket}"} = $connection;
}

sub disconnect_socket {
	my ($self, $socket) = @_;
	my $connection = $self->{socket_data}{"$socket"};
	unless (defined $connection) {
		warn "missing connection object for $socket";
		return
	}
	# say "disconnecting socket $socket";

	$connection->on_disconnect($self);
	$self->{selector}->remove($socket);
	# NOTE FOR FUTURE: closing the socket before removing it from the selector will result in a glitched and broken selector
	$socket->close;
	# say "deleted socket data for $socket";
	delete $self->{socket_data}{"$socket"};
}

sub disconnect_connection {
	my ($self, $connection) = @_;

	$self->disconnect_socket($connection->{socket});
}

sub on_data {
	my ($self, $socket) = @_;
	my $connection = $self->{socket_data}{"$socket"};
	unless (defined $connection) {
		warn "missing connection object for $socket";
		return
	}

	my $len;
	do {
		$len = read $socket, $connection->{buffer}, 4096, length $connection->{buffer};
		# say "got data from $socket: ", unpack 'H*', $buffer if $len;
	} while ($len);

	# say "read " . length $connection->{buffer};
	warn "nothing read from socket $socket ($connection->{peer_address})" unless length $connection->{buffer};

	$connection->on_data($self);
}

sub main {
	$SIG{PIPE} = 'IGNORE';
	Mirror::Reflective->new->start;
}

caller or main(@ARGV);
