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
use SSLCertificateFactory;

# $IO::Socket::SSL::DEBUG = 3;



sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{cert_factory} = SSLCertificateFactory->new;

	return $self
}

sub new_socket {
	my ($self, $socket) = @_;
	$self->new_connection(Mirror::Enchanted::ClientConnection->new($socket));
}

sub main {
	$SIG{PIPE} = 'IGNORE';
	Mirror::Enchanted->new->start;
}

caller or main(@ARGV);
