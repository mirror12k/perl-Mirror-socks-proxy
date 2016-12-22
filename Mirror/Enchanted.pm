#!/usr/bin/env perl
package Mirror::Enchanted;
use parent 'Mirror::Reflective';
use strict;
use warnings;

use feature 'say';

use Mirror::Enchanted::ServiceConnection;
use Mirror::Enchanted::ClientConnection;
use SSLCertificateFactory;



=pod

=head1 Mirror::Enchanted

an effective http and https intercepting proxy as a socks4/4a server.
this is a callable package, so you can call `perl Mirror/Enchanted.pm` to immediately initialize a new server.

the ssl intercepting is securely established using freshly created certificates with SSLCertificateFactory.
note that you will need to generate a root CA certificate and install it in your browser in order to have error-less communication.

note: the code cheats a little with ssl by simply looking for port 443.
optimally the server would peek the socket and read an ssl frame from it.
also note that websockets and anything else other than http is unsupported.

=head2 Mirror::Enchanted->new(%args)

creates a new mirror server. pass in a 'port' argument to specify the server port, defaults to 3210.

make sure to set $SIG{PIPE} = 'IGNORE'; to prevent sigpipes from killing the server.

=cut

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

# override new_socket to instantiate our special connection class with all of our logic in it
sub new_socket {
	my ($self, $socket) = @_;
	$self->new_connection(Mirror::Enchanted::ClientConnection->new($socket));
}

=head2 $mir->on_request($con, $req)

overridable event called when a new HTTP/HTTPS request is recieved by a client connection.

this event is allowed to modify the HTTP::Request $req object as necessary, and the modified object will be sent to the destination server.

must return undef normally.
alternatively return an HTTP::Response object to prevent the request from being sent and immediately send back a response.

=cut

sub on_request {
	my ($self, $con, $req) = @_;
	say "got request: ", $req->method . " " . $req->uri;

	return
}

=head2 $mir->on_response($con, $req, $res)

overridable event called when a full HTTP/HTTPS response with content is recieved by a service connection. the last known HTTP::Request is also passed in as $req.

currently no extentions are allowed (TODO).

=cut

sub on_response {
	my ($self, $con, $req, $res) = @_;
	say "got response to ", $req->method . " " . $req->uri, " : ", $res->status_line;

	return $res
}

sub main {
	$SIG{PIPE} = 'IGNORE';
	Mirror::Enchanted->new->start;
}

caller or main(@ARGV);
