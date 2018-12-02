#!/usr/bin/env perl
package Mirror::Cursed;
use parent 'Mirror::Enchanted';
use strict;
use warnings;

use feature 'say';

use Gzip::Faster;

use Sugar::IO::File;



=pod

=head1 Mirror::Cursed

an extension of Mirror::Enchanted.
this proxy will inject a script include into every html response based on the inject_script_file argument.
this is a callable package, you run `perl Mirror/Cursed.pm` to immediately initialize a new server.

=head2 Mirror::Cursed->new(%args)

specify an inject_script_file argument to inject the given javascript file into the page.

=cut

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{inject_script_file} = Sugar::IO::File->new($args{inject_script_file} // die "missing inject_script_file argument");
	die "file $self->{inject_script_file} does not exist" unless $self->{inject_script_file}->exists;

	return $self
}

# override handshake for our local injector domain
sub on_socks4_handshake {
	my ($self, $con, $hostport) = @_;

	if ($hostport eq 'injector.local:80' or $hostport eq 'injector.local:443') {
		# if the request comes for injector.local, return a mock connection
		$con->{is_local_injector_connection} = 1;
		return undef;
	}
	return $self->SUPER::on_socks4_handshake($con, $hostport);
}

# override requests for our mock connections
sub on_request {
	my ($self, $con, $req) = @_;
	say "got request: ", $req->method . " " . $req->uri;

	if ($con->{is_local_injector_connection}) {
		# if this is a local injector connection, return our injection script
		my $res = HTTP::Response->new('200', 'OK');
		$res->content($self->{inject_script_file}->read);

		$res->protocol('HTTP/1.1');
		$res->header('content-type' => 'application/javascript');
		$res->header('content-length' => length $res->content);

		return $res;
	} else {
		# modify the content-encoding header so that we can actually read the data from the server
		$req->remove_header('accept-encoding');
		$req->header('accept-encoding' => 'gzip, deflate');
	}

	return;
}

# override responses to inject our script tag into htmls
sub on_response {
	my ($self, $con, $req, $res) = @_;
	say "got response to ", $req->method . " " . $req->uri, " : ", $res->status_line;

	# if the content is html, inject our script
	my $content_type = $res->header('content-type');
	if (defined $content_type and $content_type =~ /\btext\/html\b/) {
		# get the content and prepend our script to it
		my $content = $res->decoded_content;
		$content = "<script src=\"https:\/\/injector.local\"><\/script>$content";

		# encode otherwise utf8 gets in a fight with HTTP::Message
		$content = gzip ("$content");

		# reset the encoding to our own
		$res->remove_header('content-encoding');
		$res->header('content-encoding' => 'gzip');
		# # update the content and content length
		$res->remove_header('content-length');
		$res->header('content-length' => length $content);
		$res->content($content);
		# clear any security policy
		$res->remove_header('content-security-policy');
	}


	return $res;
}

sub main {
	my ($inject_script_file) = @_;
	$SIG{PIPE} = 'IGNORE';
	__PACKAGE__->new(inject_script_file => $inject_script_file)->start;
}

caller or main(@ARGV);
