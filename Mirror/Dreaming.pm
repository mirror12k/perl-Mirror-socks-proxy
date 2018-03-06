#!/usr/bin/env perl
package Mirror::Dreaming;
use parent 'Mirror::Enchanted';
use strict;
use warnings;

use feature 'say';

use HTTP::Response;

use Mirror::Dreaming::ClientConnection;



sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{dreams_data_directory} = 'dreams_data';
	$self->{dream_urls} = [ Sugar::IO::File->new("$self->{dreams_data_directory}/urls")->readlines ];
	$self->{dream_headers} = [ Sugar::IO::File->new("$self->{dreams_data_directory}/headers")->readlines ];
	$self->{dream_body_files} = [ Sugar::IO::Dir->new("$self->{dreams_data_directory}/body")->files ];

	return $self;
}

sub get_random_header {
	my ($self) = @_;

	my $random_header;
	do {
		$random_header = $self->{dream_headers}[int rand @{$self->{dream_headers}}];
	} while ($random_header =~ /\A(content-type|content-length|content-encoding|transfer-encoding):/);

	return $random_header;
}

sub get_random_html_tags {
	my ($html) = @_;

	my @tags;
	while ($html =~ /<([a-zA-Z_][a-zA-Z_0-9]*)\b[^>]*?(\/\s*>|>.*?<\/\1>)/sg) {
		pos ($html) = $+[1];
		push @tags, $&;
	}

	# return @tags;
	my $count = 4 + int rand 20;
	return map $tags[int rand @tags], 1 .. $count;
}

sub substitute_html_tags {
	my ($html, $replacement) = @_;

	die "not a tag" unless $replacement =~/\A<([a-zA-Z_][a-zA-Z_0-9]*)\b/s;
	my $replacement_tag = lc $1;

	while ($html =~ /<([a-zA-Z_][a-zA-Z_0-9]*)\b[^>]*?(\/\s*>|>.*?<\/\1>)/sg) {
		if ($replacement_tag eq lc $1) {
			if (rand() < 0.1) {
				substr($html, $-[0], $+[0] - $-[0]) = $replacement;
			}
		}
		pos ($html) = $+[1];
	}

	return $html;
}

sub get_random_html {
	my ($self) = @_;

	my $file = $self->{dream_body_files}[int rand @{$self->{dream_body_files}}];
	say "getting file: $file";
	return $file->read;
}

sub generate_random_headers {
	my ($self) = @_;
	my $count = int rand 20;
	return map $self->get_random_header, 1 .. $count;
}

# override new_socket to instantiate our special connection class with all of our logic in it
sub new_socket {
	my ($self, $socket) = @_;
	$self->new_connection(Mirror::Dreaming::ClientConnection->new($socket));
}


sub on_request {
	my ($self, $con, $req) = @_;
	say "got request: ", $req->method . " " . $req->uri;

	my $donor_html = $self->get_random_html;
	my $victim_html = $self->get_random_html;
	$victim_html = substitute_html_tags($victim_html, $_) foreach get_random_html_tags($donor_html);
	my $body = $victim_html;

	my $text = "HTTP/1.1 200 OK\r\n" . (join '', map "$_\r\n", $self->generate_random_headers)
		. "Content-Length: " . length($body) . "\r\n"
		. "\r\n";

	# my $res = HTTP::Response->parse("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n");
	my $res = HTTP::Response->parse("$text$body");
	return $res
}

# sub on_response {
# 	my ($self, $con, $req, $res) = @_;
# 	say "got response to ", $req->method . " " . $req->uri, " : ", $res->status_line;

# 	return $res
# }

sub main {
	$SIG{PIPE} = 'IGNORE';
	Mirror::Dreaming->new->start;
}

caller or main(@ARGV);
