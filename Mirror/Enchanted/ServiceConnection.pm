package Mirror::Enchanted::ServiceConnection;
use parent 'Mirror::Enchanted::ClientConnection';
use strict;
use warnings;

use feature 'say';

use IO::Select;
use Iron::TCP;
use Iron::SSL;
use HTTP::Response;



sub on_data {
	my ($self, $mir) = @_;

	if ($self->{is_header}) {
		if ($self->{buffer} =~ /\r?\n\r?\n/s) {
			$self->{buffer} = $';
			my $res = HTTP::Response->parse("$`\r\n\r\n");
			$self->{response} = $res;
			$res = $self->process_response_head($res);
			warn "may have just got a sigpipe" unless $self->{paired_connection}{socket}->print($res->as_string);

			if (defined $res->header('Content-Length') and 0 < int $res->header('Content-Length')) {
				$self->{is_header} = 0;
				$self->{content_length} = int $res->header('Content-Length');

				$self->on_data($mir) if length $self->{buffer};
			}
		}
	} else {
		if (length $self->{buffer} >= $self->{content_length}) {
			$self->{response}->content(substr $self->{buffer}, 0, $self->{content_length});
			$self->{buffer} = substr $self->{buffer}, $self->{content_length};
			$self->{response} = $self->process_response($self->{response});
			$self->{is_header} = 1;

			warn "may have just got a sigpipe" unless $self->{paired_connection}{socket}->print($self->{response}->content);
		}
	}
}

sub process_response_head {
	my ($self, $req) = @_;

	say "got response head: ", $req->as_string;

	return $req
}

sub process_response {
	my ($self, $req) = @_;

	# say "got response: ", $req->as_string;

	return $req
}

1;
