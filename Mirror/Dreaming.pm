#!/usr/bin/env perl
package Mirror::Dreaming;
use parent 'Mirror::Enchanted';
use strict;
use warnings;

use feature 'say';

use JSON;
use HTTP::Response;

use Sugar::IO::File;
use Sugar::IO::Dir;



=pod

=head1 Mirror::Dreaming

extension of Mirror::Enchanted's http/https intercepting proxy.

takes an http_log directory which was written by Mirror::Crystalline and replays the responses based on requests.
can only play responses which match the domain, port, uri, and method of the request.
otherwise it returns a 404 response.

=head2 Mirror::Dreaming->new(%args)

specify a dream_logs_directory argument to play the responses from that http_log directory.

=cut

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{dream_logs_directory} = $args{dream_logs_directory} // 'http_history';
	$self->load_logs_directory($self->{dream_logs_directory});

	return $self;
}

sub load_logs_directory {
	my ($self, $directory) = @_;

	my $headers_log = decode_json(Sugar::IO::File->new("$directory/headers.json")->read);

	foreach my $dream_log (@$headers_log) {
		push @{$self->{dreams_by_request}{$dream_log->{request}{url}}{$dream_log->{request}{method}}}, $dream_log;
	}
}



sub on_socks4_handshake {
	my ($self, $con, $hostport) = @_;
	# mock all connections
	return;
}

sub on_request {
	my ($self, $con, $req) = @_;
	say "got request: ", $req->method . " $con->{requested_connection_hostport}" . $req->uri;

	# get the necessary request variables
	my $method = $req->method;
	my $protocol = $con->{is_ssl} ? 'https://' : 'http://';
	my $uri = $req->uri;
	my $request_identifier = "${protocol}$con->{requested_connection_hostport}${uri}";
	# say "debug request_identifier: $request_identifier";

	if (exists $self->{dreams_by_request}{$request_identifier}
			and exists $self->{dreams_by_request}{$request_identifier}{$method}) {
		my $dream_log = $self->{dreams_by_request}{$request_identifier}{$method}[0];

		# build the response
		my $res = HTTP::Response->new($dream_log->{response}{code}, $dream_log->{response}{message});
		$res->protocol($dream_log->{response}{protocol});
		foreach my $key (keys %{$dream_log->{response}{headers}}) {
			$res->header($key => $dream_log->{response}{headers}{$key});
		}
		# get the content
		my $content;
		my $body_file = "$self->{dream_logs_directory}/$dream_log->{_timestamp}_res.body";
		if (-e -f $body_file) {
			$content = Sugar::IO::File->new($body_file)->read;
		} else {
			$content = '';
		}
		$res->content($content);

		# replace any transfer encoding header if set
		if (defined $res->header('transfer-encoding') and lc($res->header('transfer-encoding')) eq 'chunked') {
			$res->remove_header('transfer-encoding');
			$res->header('content-length' => length $content);
		}

		say "\tsending dream response: $dream_log->{_timestamp}";
		# say "response: ", $res->as_string;

		return $res;
	} else {
		# return a fake 404 response
		my $res = HTTP::Response->new('404', 'Not Found');
		$res->protocol('HTTP/1.1');
		$res->header('content-length' => 0);

		say "\t!!! no dream data found for this request !!!";

		return $res;
	}
}

sub main {
	$SIG{PIPE} = 'IGNORE';
	__PACKAGE__->new->start;
}

caller or main(@ARGV);
