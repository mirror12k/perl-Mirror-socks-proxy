#!/usr/bin/env perl
package Mirror::Reflective;
use parent 'Mirror::Server';
use strict;
use warnings;

use feature 'say';

use Mirror::Reflective::ClientConnection;



=pod

=head1 Mirror::Reflective

an efficient socks4/4a proxy server.
this is a callable package, so you can call `perl Mirror/Reflective.pm` to immediately initialize a new server.

=cut

=head2 Mirror::Reflective->new(%args)

creates a new mirror server. pass in a 'port' argument to specify the server port, defaults to 3210.

make sure to set $SIG{PIPE} = 'IGNORE'; to prevent sigpipes from killing the server.

=cut

# override new_socket to instantiate our special connection class with all of our logic in it
sub new_socket {
	my ($self, $socket) = @_;
	$self->new_connection(Mirror::Reflective::ClientConnection->new($socket));
}

# override to intercept and manipulate the hostport if you'd like
# whichever hostport string is returned will be used as the destination connection
sub on_socks4_handshake {
	my ($self, $con, $hostport) = @_;
	say "socks4 connection request: $hostport";
	return $hostport
}

sub main {
	$SIG{PIPE} = 'IGNORE';
	Mirror::Reflective->new->start;
}

caller or main(@ARGV);
