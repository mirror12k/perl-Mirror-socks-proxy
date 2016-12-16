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
			$res = $mir->on_response_head($self, $res);
			$self->{paired_connection}->print($res->as_string);

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
			}
		}
	} elsif (defined $self->{content_length}) {
		if (length $self->{buffer} >= $self->{content_length}) {
			$self->{response}->content(substr $self->{buffer}, 0, $self->{content_length});
			$self->{buffer} = substr $self->{buffer}, $self->{content_length};
			$self->{response} = $mir->on_response($self, $self->{response});
			$self->{is_header} = 1;

			$self->{paired_connection}->print($self->{response}->content);
		}
	} elsif (defined $self->{chunked_content_length} and length $self->{buffer} >= $self->{chunked_content_length} + 2) {
		$self->{response}->content($self->{response}->content . substr $self->{buffer}, 0, $self->{chunked_content_length});
		$self->{buffer} = substr $self->{buffer}, $self->{chunked_content_length} + 2;

		if ($self->{chunked_content_length} == 0) {
			$self->{is_header} = 1;
			$self->{response} = $mir->on_response($self, $self->{response});
			my $length_info = sprintf "%x\r\n", length $self->{response}->content;

			my $data = $length_info . $self->{response}->content . "\r\n0\r\n\r\n";
			$self->{paired_connection}->print($data);
		}
		$self->{chunked_content_length} = undef;
		
		$self->on_data($mir) if length $self->{buffer};
	} elsif ($self->{buffer} =~ /\A([a-fA-F0-9]+)\r?\n/) {
		my $len = hex $1;
		$self->{buffer} = $';
		# warn "got len: $len";
		# if ($len == 0) {
		# } else {
		$self->{chunked_content_length} = $len;
		# }
		$self->on_data($mir) if length $self->{buffer};
	}
}

1;
