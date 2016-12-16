#!/usr/bin/env perl
package Mirror::Reflective;
use strict;
use warnings;

use feature 'say';

use IO::Select;
use Iron::TCP;
use IO::Socket::INET;
use IO::Socket::SSL;

use Mirror::Reflective::ClientConnection;



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
		# say "debug: $len";
		# say "got data from $socket: ($len) ", unpack 'H*', $connection->{buffer} if $len;
	} while ($len);

	# say "read " . length $connection->{buffer};
	# warn "nothing read from socket $socket ($connection->{peer_address}) : $!, $SSL_ERROR" unless length $connection->{buffer};
	unless (length $connection->{buffer}) {
		if (defined $SSL_ERROR and $SSL_ERROR eq SSL_WANT_READ) {
			# do nothing, according to openssl docs this is a "something moved but not enough"
		# } elsif ($socket->errstr eq SSL_WANT_READ) {
			# do nothing, according to openssl docs this is a "something moved but not enough"
		# } elsif ($SSL_ERROR eq '') {
			# warn "empty read from ", $socket->fileno;
		} else {
			warn "nothing read from socket ", $socket->fileno, " ($connection->{peer_address}) : ", join ', ', $!, defined $SSL_ERROR ? $SSL_ERROR : '';
			$self->disconnect_connection($connection);
		}
	} else {
		$connection->on_data($self);
	}
}

sub main {
	$SIG{PIPE} = 'IGNORE';
	Mirror::Reflective->new->start;
}

caller or main(@ARGV);
