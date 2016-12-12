package Mirror::Reflective::ServiceConnection;
use strict;
use warnings;

use feature 'say';

use IO::Select;
use Iron::TCP;
use IO::Socket::INET;



sub new {
	my ($class, $socket, %args) = @_;
	my $self = bless { buffer => '', socket => $socket, %args }, $class;
	return $self
}

sub on_connect {
	my ($self, $mir) = @_;
	say "new " . ref ($self) . " connection $self->{peer_address}";
}

sub on_data {
	my ($self, $mir) = @_;

	# say "$self->{peer_address} >>> $self->{paired_connection}{peer_address}";
	$self->{paired_connection}{socket}->print($self->{buffer});
	$self->{buffer} = '';
}

sub on_disconnect {
	my ($self, $mir) = @_;
	say "disconnected " . ref ($self) . " connection $self->{peer_address}";
	# say "disconnected client $self->{peer_address}";

	if (defined $self->{paired_connection}) {
		say "disconnecting paired connection";
		my $paired_connection = $self->{paired_connection};
		delete $self->{paired_connection}{paired_connection};
		delete $self->{paired_connection};
		$mir->disconnect_connection($paired_connection);
	}
}

1;
