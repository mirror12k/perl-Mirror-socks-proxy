#!/usr/bin/env perl
package Mirror::Crystalline;
use parent 'Mirror::Enchanted';
use strict;
use warnings;

use feature 'say';

use JSON;

use Sugar::IO::File;
use Sugar::IO::Dir;



=pod

=head1 Mirror::Crystalline

extension of Mirror::Enchanted's http/https intercepting proxy.

stores all request/response data it receives in a sorted json log (format inspired by HAR format)
with bodies being stored seperately in individual timestamped files.
recorded logs can then be played back with Mirror::Dreaming in order to view the snap-shot of history as it was.

=head2 Mirror::Crystalline->new(%args)

creates a new mirror server. see Mirror::Enchanted for any inherited arguments. other optional arguments:

store_bodies: defaults to 1. bool which dictates whether to store request and response bodies in files or to skip them.

logs_directory: defaults to "http_history". directory path where the logs will be written to. must already exist before hand otherwise ->new dies.

log_file: defaults to "$self->{logs_directory}/http_log". filepath to store the primary entry log in. any current contents will be preserved.

make sure to set $SIG{PIPE} = 'IGNORE'; to prevent sigpipes from killing the server.

=cut


sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{store_bodies} = $args{store_bodies} // 1;
	$self->{logs_directory} = Sugar::IO::Dir->new($args{logs_directory} // 'http_history');
	$self->{log_file} = Sugar::IO::File->new($args{log_file} // "$self->{logs_directory}/headers.json");
	$self->{replace_encoding} = $args{replace_encoding} // 1;
	$self->{log_file_first_write} = 1;

	die "please create the logs_directory at '$self->{logs_directory}'" unless $self->{logs_directory}->exists;

	return $self
}

sub encode_reqres_headers {
	my ($self, $con, $req, $res) = @_;

	my $client_connection = $con->{paired_connection};
	my $protocol = $client_connection->{is_ssl} ? 'https://' : 'http://';

	my $data = {
		_timestamp => "$self->{timestamp}_$self->{timestamp_index_formatted}",
		request => {
			protocol => $req->protocol,
			method => $req->method,
			url => "$protocol$client_connection->{socks_hostport}" . $req->uri,
		},
		response => {
			protocol => $res->protocol,
			code => $res->code,
			message => $res->message,
		},
	};

	$data->{request}{headers} = { $req->headers->flatten };
	$data->{response}{headers} = { $res->headers->flatten };

	return JSON->new->canonical->encode($data)
}

sub output_reqres {
	my ($self, $con, $req, $res) = @_;
	if (not defined $self->{timestamp} or $self->{timestamp} != time) {
		$self->{timestamp} = time;
		$self->{timestamp_index} = 0;
	} else {
		$self->{timestamp_index}++;
	}
	$self->{timestamp_index_formatted} = sprintf "%03d", $self->{timestamp_index};

	my $prefix = $self->{log_file_first_write} ? '[' : ',';
	$self->{log_file_first_write} = 0;

	$self->{log_file}->append($prefix . $self->encode_reqres_headers($con, $req, $res));

	if ($self->{store_bodies}) {
		if (length $req->content) {
			my $req_file = $self->{logs_directory}->new_file("$self->{timestamp}_$self->{timestamp_index_formatted}_req.body");
			$req_file->write($req->content);
		}

		if (length $res->content) {
			my $res_file = $self->{logs_directory}->new_file("$self->{timestamp}_$self->{timestamp_index_formatted}_res.body");
			$res_file->write($res->content);
		}
	}
}

sub on_request {
	my ($self, $con, $req) = @_;

	if ($self->{replace_encoding} and defined $req->header('accept-encoding')) {
		$req->remove_header('accept-encoding');
		$req->header('accept-encoding' => 'gzip');
	}

	return;
}

sub on_response {
	my ($self, $con, $req, $res) = @_;

	$self->output_reqres($con, $req, $res);

	return $self->SUPER::on_response($con, $req, $res);
}

sub main {
	$SIG{PIPE} = 'IGNORE';

	my $svr = __PACKAGE__->new;

	$SIG{INT} = sub {
		$svr->{log_file}->append(']');
		die "server shutdown";
	};

	$svr->start;
}

caller or main(@ARGV);
