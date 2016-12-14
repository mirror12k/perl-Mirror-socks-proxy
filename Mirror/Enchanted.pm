#!/usr/bin/env perl
package Mirror::Enchanted;
use parent 'Mirror::Reflective';
use strict;
use warnings;

use feature 'say';

use IO::Select;
use Iron::TCP;
use IO::Socket::SSL;

use Mirror::Enchanted::ServiceConnection;
use Mirror::Enchanted::ClientConnection;

sub new_socket {
	my ($self, $socket) = @_;

	# if ($socket->peerport == 443) {
	# 	$self->new_connection(Mirror::Enchanted::ClientConnection->new($socket, is_ssl => 1)) if $socket;
	# } else {
	# }
	$self->new_connection(Mirror::Enchanted::ClientConnection->new($socket));
}

sub main {
	$SIG{PIPE} = 'IGNORE';
	Mirror::Enchanted->new->start;
}

caller or main(@ARGV);
