package Mirror::Server;
use strict;
use warnings;

use feature 'say';

use IO::Select;
use Iron::TCP;
use IO::Socket::INET;
use IO::Socket::SSL;

use Mirror::SocketConnection;
use Mirror::PairedConnection;



=pod

=head1 Mirror::Server

a base class implementing an event-oriented select-ing networking server.
the server contains one primary event loop focused on awaiting an IO::Select object to return a pending network events.
after creating it, call ->start to start the event loop.

when creating a Mirror::Server, you should set $SIG{PIPE} = 'IGNORE'; because sigpipes are common in this server architecture.

to use this server effectively, one should extend it, and override the new_socket method to produce connections of a useful type.
any connnection logic should then be placed into the connection class (recommended to subclass Mirror::SocketConnection).

=head2 Mirror::Server->new(%args)

creates a new mirror server. pass in a 'port' argument to specify the server port, defaults to 3210.

=cut

sub new {
	my ($class, %args) = @_;
	my $self = bless {}, $class;

	$self->{port} = $args{port} // 3210;
	$self->{socket_connections} = {};

	return $self
}

=head2 $mir->setup

internal overridable method called right before ->start.
initializes the server accepting socket and the IO::Select interface.

=cut

sub setup {
	my ($self) = @_;

	$self->{server_socket} = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalPort => $self->{port},
		Listen => SOMAXCONN,
		Reuse => 1,
		# Blocking => 1,
	) or die "ERROR: failed to set up listening socket: $!";
	$self->{selector} = IO::Select->new($self->{server_socket});

	say ref($self) . " listening on port $self->{port}";
}

=head2 $mir->start

start the event loop. sets the $mir->{running} variable to 1. set it to 0 to stop the event loop running.

=cut

sub start {
	my ($self) = @_;

	$self->setup;

	$self->{running} = 1;
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

=head2 $mir->new_socket($socket)

overridable method called when a new socket is connected through the server socket.
call $self->new_connection with a connection object created from the given socket.

=cut

sub new_socket {
	my ($self, $socket) = @_;

	warn "unimplemented new_socket method in ", ref($self);
	$self->new_connection(Mirror::SocketConnection->new($socket));
}

sub new_connection {
	my ($self, $connection) = @_;

	$connection->{socket}->blocking(0);

	my $peer_ip = join '.', map ord, split '', $connection->{socket}->peeraddr;
	my $peer_port = $connection->{socket}->peerport;
	$connection->{peer_address} = "$peer_ip:$peer_port";

	$self->{socket_connections}{"$connection->{socket}"} = $connection;
	$connection->on_connect($self);

	$self->{selector}->add($connection->{socket});
}

=head2 $mir->update_connection_socket($old_socket, $connection)

utility method for connections which change their socket objects (such as a connection upgrading a IO::Socket::INET to a IO::Socket::SSL).

=cut

sub update_connection_socket {
	my ($self, $old_socket, $connection) = @_;
	delete $self->{socket_connections}{"$old_socket"};
	$self->{socket_connections}{"$connection->{socket}"} = $connection;
}

# event when a socket has reached eof
sub disconnect_socket {
	my ($self, $socket) = @_;
	my $connection = $self->{socket_connections}{"$socket"};
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
	delete $self->{socket_connections}{"$socket"};
}

=head2 $mir->disconnect_connection($connection)

utility method to immediately close and disconnect a connection object.
this should be called by a connection when it encounters an unrecoverable error.

=cut

sub disconnect_connection {
	my ($self, $connection) = @_;
	$self->disconnect_socket($connection->{socket});
}

# event when a socket has data ready to read. this method will safely read all the data available into $connection->{buffer}.
sub on_data {
	my ($self, $socket) = @_;
	my $connection = $self->{socket_connections}{"$socket"};
	unless (defined $connection) {
		warn "missing connection object for $socket";
		return
	}
	my $len;
	do {
		$len = read $socket, $connection->{buffer}, 4096, length $connection->{buffer};
	} while ($len);

	# say "read " . length $connection->{buffer};
	unless (length $connection->{buffer}) {
		if (defined $SSL_ERROR and $SSL_ERROR eq SSL_WANT_READ) {
			# do nothing, according to openssl docs this is a "something moved but not enough"
		} else {
			warn "nothing read from socket ", $socket->fileno, " ($connection->{peer_address}) : ", join ', ', $?, $!, defined $SSL_ERROR ? $SSL_ERROR : '';
			$self->disconnect_connection($connection);
		}
	} else {
		$connection->on_data($self);
	}
}

1;
