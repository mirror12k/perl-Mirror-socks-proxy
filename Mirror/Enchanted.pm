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



sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{cert_factory} = SSLCertificateFactory->new(
		root_key => 'ssl_factory_config/rootkey.pem',
		root_certificate => 'ssl_factory_config/root.pem',
		certificate_key => 'ssl_factory_config/key.pem',
		certificate_request => 'ssl_factory_config/request.csr',
	);

	return $self
}

sub new_socket {
	my ($self, $socket) = @_;
	$self->new_connection(Mirror::Enchanted::ClientConnection->new($socket));
}

sub on_request {
	my ($self, $con, $req) = @_;
	say "got request: ", $req->method . " " . $req->uri;

	return
}

sub on_response_head {
	my ($self, $con, $res) = @_;

	say "got response head: ", $res->status_line;

	return $res
}

sub on_response {
	my ($self, $con, $res) = @_;

	say "got response: ", $res->status_line;

	return $res
}

sub main {
	$SIG{PIPE} = 'IGNORE';
	Mirror::Enchanted->new->start;
}

caller or main(@ARGV);
