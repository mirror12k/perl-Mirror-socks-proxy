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

=head2 Mirror::Crystalline->new(%args)

creates a new mirror server. see Mirror::Enchanted for any inherited arguments. other optional arguments:

suffix_headers: defaults to 1. specifies the format to write to the logs. if 1, it will specifically place the headers towards the end of the log entry.

store_bodies: defaults to 1. bool which dictates whether to store request and response bodies in files or to skip them.

logs_directory: defaults to "http_history". directory path where the logs will be written to. must already exist before hand otherwise ->new dies.

log_file: defaults to "$self->{logs_directory}/http_log". filepath to store the primary entry log in. any current contents will be preserved.

make sure to set $SIG{PIPE} = 'IGNORE'; to prevent sigpipes from killing the server.

=cut


sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{suffix_headers} = $args{suffix_headers} // 1;
	$self->{store_bodies} = $args{store_bodies} // 1;
	$self->{logs_directory} = Sugar::IO::Dir->new($args{logs_directory} // 'http_history');
	$self->{log_file} = Sugar::IO::File->new($args{log_file} // "$self->{logs_directory}/http_log");

	die "please create the logs_directory at '$self->{logs_directory}'" unless $self->{logs_directory}->exists;

	return $self
}

sub encode_reqres_headers {
	my ($self, $req, $res) = @_;

	my $data = {
		_timestamp => "$self->{timestamp}_$self->{timestamp_index_formatted}",
		request => {
			protocol => $req->protocol,
			method => $req->method,
			url => '' . $req->uri, # TODO
		},
		response => {
			protocol => $res->protocol,
			code => $res->code,
			message => $res->message,
		},
	};

	if ($self->{suffix_headers}) {
		$data->{zheaders} = {
			request_headers => { $req->headers->flatten },
			response_headers => { $res->headers->flatten },
		};
	} else {
		$data->{request}{headers} = { $req->headers->flatten };
		$data->{response}{headers} = { $res->headers->flatten };
	}

	return JSON->new->canonical->encode($data)
}

sub output_reqres {
	my ($self, $req, $res) = @_;
	if (not defined $self->{timestamp} or $self->{timestamp} != time) {
		$self->{timestamp} = time;
		$self->{timestamp_index} = 0;
	} else {
		$self->{timestamp_index}++;
	}
	$self->{timestamp_index_formatted} = sprintf "%02d", $self->{timestamp_index};

	my $log_file = $self->{log_file};
	$log_file->append($self->encode_reqres_headers($req, $res) . ",\n");

	if ($self->{store_bodies}) {
		if (length $req->content) {
			my $req_file = $self->{logs_directory}->new_file("$self->{timestamp}_$self->{timestamp_index_formatted}_req");
			$req_file->write($req->decoded_content);
		}

		if (length $res->content) {
			my $res_file = $self->{logs_directory}->new_file("$self->{timestamp}_$self->{timestamp_index_formatted}_res");
			$res_file->write($res->decoded_content);
		}
	}
}

sub on_response {
	my ($self, $con, $req, $res) = @_;

	$self->output_reqres($req, $res);

	return $self->SUPER::on_response($con, $req, $res);
}

sub main {
	$SIG{PIPE} = 'IGNORE';
	Mirror::Crystalline->new->start;
}

caller or main(@ARGV);
