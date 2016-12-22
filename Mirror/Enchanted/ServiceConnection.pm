package Mirror::Enchanted::ServiceConnection;
use parent 'Mirror::Enchanted::ClientConnection';
use strict;
use warnings;

use feature 'say';

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

			if (defined $res->header('Content-Length') and 0 < int $res->header('Content-Length')) {
				$self->{is_header} = 0;
				$self->{content_length} = int $res->header('Content-Length');

				$self->on_data($mir) if length $self->{buffer};
			} elsif (defined $res->header('Transfer-Encoding') and 'chunked' eq lc $res->header('Transfer-Encoding')) {
				$self->{is_header} = 0;
				$self->{content_length} = undef;
				$self->{chunked_content_length} = undef;

				$self->{response}->content('');

				$self->on_data($mir) if length $self->{buffer};
			} else {
				$res = $mir->on_response($self, $self->{request}, $res);
				$self->{paired_connection}->print($res->as_string);
			}
		}
	} elsif (defined $self->{content_length}) {
		if (length $self->{buffer} >= $self->{content_length}) {
			$self->{is_header} = 1;
			$self->{response}->content(substr $self->{buffer}, 0, $self->{content_length});
			$self->{buffer} = substr $self->{buffer}, $self->{content_length};
			$self->{response} = $mir->on_response($self, $self->{request}, $self->{response});

			$self->{paired_connection}->print($self->{response}->as_string);
		}
	} elsif (defined $self->{chunked_content_length} and length $self->{buffer} >= $self->{chunked_content_length} + 2) {
		$self->{response}->content($self->{response}->content . substr $self->{buffer}, 0, $self->{chunked_content_length});
		$self->{buffer} = substr $self->{buffer}, $self->{chunked_content_length} + 2;

		if ($self->{chunked_content_length} == 0) {
			$self->{is_header} = 1;
			$self->{response} = $mir->on_response($self, $self->{request}, $self->{response});

			my $content = $self->{response}->content;
			my $length_info = sprintf "%x\r\n", length $content;
			$self->{response}->content("$length_info$content\r\n0\r\n\r\n");
			$self->{paired_connection}->print($self->{response}->as_string);
			$self->{response}->content($content);
		}
		$self->{chunked_content_length} = undef;
		
		$self->on_data($mir) if length $self->{buffer};
	} elsif ($self->{buffer} =~ /\A([a-fA-F0-9]+)\r?\n/) {
		$self->{buffer} = $';
		$self->{chunked_content_length} = hex $1;

		$self->on_data($mir) if length $self->{buffer};
	}
}

1;
