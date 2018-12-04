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
or it can play random responses based on expected content-type for browser stress testing.

start with C<./Mirror/Dreaming.pm> for a replay proxy or C<./Mirror/Dreaming.pm --scattered> for a fuzzy proxy.

=head2 Mirror::Dreaming->new(%args)

specify a dream_logs_directory argument to play the responses from that http_log directory.

=cut

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{dream_logs_directory} = $args{dream_logs_directory} // 'http_history';
	$self->{is_scattered} = $args{is_scattered} // 0;

	if ($self->{is_scattered}) {
		$self->load_logs_directory_by_type($self->{dream_logs_directory});
	} else {
		$self->load_logs_directory_by_identifier($self->{dream_logs_directory});
	}

	return $self;
}

sub load_logs_directory_by_identifier {
	my ($self, $directory) = @_;

	my $headers_log = decode_json(Sugar::IO::File->new("$directory/headers.json")->read);

	foreach my $dream_log (@$headers_log) {
		push @{$self->{dreams_by_request}{$dream_log->{request}{url}}{$dream_log->{request}{method}}}, $dream_log;
	}
}

sub load_logs_directory_by_type {
	my ($self, $directory) = @_;

	my $headers_log = decode_json(Sugar::IO::File->new("$directory/headers.json")->read);

	foreach my $dream_log (@$headers_log) {
		push @{$self->{dreams_by_content_type}{$dream_log->{request}{url}}{$dream_log->{request}{method}}}, $dream_log;

		my ($content_type_key) = grep { 'content-type' eq lc $_ } keys %{$dream_log->{response}{headers}};
		if (defined $content_type_key) {
			my ($content_type) = map s/\A\s*(.*?)\s*\Z/$1/rs, split ';', $dream_log->{response}{headers}{$content_type_key};
			say "content-type: $content_type";
			push @{$self->{dreams_by_content_type}{$content_type}}, $dream_log;
		}
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

	my $content_type = $self->get_type_from_request($req);
	# say "debug request_identifier: $request_identifier";
	if ($self->{is_scattered} == 1 and exists $self->{dreams_by_content_type}{$content_type}) {

		# get the dream log and load it into a response
		my $dream_log = $self->{dreams_by_content_type}{$content_type}[
				int rand @{$self->{dreams_by_content_type}{$content_type}}];
		my $res = $self->load_response_from_dream_log($dream_log);

		say "\tsending dream response: $dream_log->{_timestamp}";
		return $res;

	} elsif ($self->{is_scattered} == 0 and exists $self->{dreams_by_request}{$request_identifier}
			and exists $self->{dreams_by_request}{$request_identifier}{$method}) {

		# get the dream log and load it into a response
		my $dream_log = $self->{dreams_by_request}{$request_identifier}{$method}[0];
		my $res = $self->load_response_from_dream_log($dream_log);

		say "\tsending dream response: $dream_log->{_timestamp}";
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

sub get_type_from_request {
	my ($self, $req) = @_;

	my $type = 'text/html';
	if ($req->uri->path =~ /\.png\Z/) {
		$type = 'image/png';
	} elsif ($req->uri->path =~ /\.jpe?g\Z/) {
		$type = 'image/jpeg';
	} elsif ($req->uri->path =~ /\.gif\Z/) {
		$type = 'image/gif';
	} elsif ($req->uri->path =~ /\.css\Z/) {
		$type = 'text/css';
	} elsif ($req->uri->path =~ /\.js\Z/) {
		$type = 'application/javascript';
	} elsif ($req->uri->path =~ /\.ico\Z/) {
		$type = 'image/x-icon';
	}

	return $type;
}

sub load_response_from_dream_log {
	my ($self, $dream_log) = @_;

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

	# say "response: ", $res->as_string;

	return $res;
}

sub get_random_html_tags {
	my ($html) = @_;

	my @tags;
	while ($html =~ /<([a-zA-Z_][a-zA-Z_0-9]*+)\b[^>]*?(\/\s*>|>.*?<\/\1>)/sg) {
		pos ($html) = $+[1];
		push @tags, $&;
	}
	return unless @tags;

	# return @tags;
	my $count = 4 + int rand 20;
	return map $tags[int rand @tags], 1 .. $count;
}

sub substitute_html_tags {
	my ($html, $replacement) = @_;

	die "not a tag: $replacement" unless $replacement =~/\A<([a-zA-Z_][a-zA-Z_0-9]*)\b/s;
	my $replacement_tag = lc $1;

	my $start_render_time = time;

	while ($html =~ /<([a-zA-Z_][a-zA-Z_0-9]*+)\b[^>]*?(\/\s*>|>.*?<\/\1>)/sg) {
		if ($replacement_tag eq lc $1) {
			if (rand() < 0.1) {
				substr($html, $-[0], $+[0] - $-[0]) = $replacement;
			}
		}
		pos ($html) = $+[1];
		if (time - $start_render_time >= 5) {
			warn "substitute_html_tags exceeded 5 second render time!";
			return $html;
		}
	}

	return $html;
}

sub mangle_html_tags {
	my ($victim_html, $donor_html) = @_;

	# say "rendering";

	my $start_render_time = time;
	foreach my $tag (get_random_html_tags($donor_html)) {
		$victim_html = substitute_html_tags($victim_html, $tag);
		if (time - $start_render_time >= 5) {
			warn "mangle_html_tags exceeded 5 second render time!";
			last;
		}
	}
	# say "done rendering";

	return $victim_html;
}

sub main {
	$SIG{PIPE} = 'IGNORE';
	__PACKAGE__->new(is_scattered => (defined $_[0] and $_[0] eq '--scattered'))->start;
}

caller or main(@ARGV);
