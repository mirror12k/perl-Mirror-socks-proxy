package Mirror::PairedConnection;
use parent 'Mirror::SocketConnection';
use strict;
use warnings;

use feature 'say';

use IO::Select;
use IO::Socket::INET;
use IO::Socket::SSL;



sub on_data {
	my ($self, $mir) = @_;
	die "undefined paired connection, don't know what to do with data in on_data" unless defined $self->{paired_connection};
	$self->{paired_connection}->print($self->{buffer});
	$self->{buffer} = '';
}

sub on_disconnect {
	my ($self, $mir) = @_;
	$self->SUPER::on_disconnect($mir);

	if (defined $self->{paired_connection}) {
		my $paired_connection = $self->{paired_connection};
		delete $self->{paired_connection}{paired_connection};
		delete $self->{paired_connection};
		$mir->disconnect_connection($paired_connection) if $paired_connection->{socket}->connected;
	}
}

1;
