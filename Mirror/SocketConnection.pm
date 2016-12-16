package Mirror::SocketConnection;
use strict;
use warnings;

use feature 'say';

use IO::Select;
use IO::Socket::INET;
use IO::Socket::SSL;



sub new {
	my ($class, $socket, %args) = @_;
	my $self = bless { buffer => '', socket => $socket, %args }, $class;
	return $self
}

sub on_connect {
	my ($self, $mir) = @_;
	warn "new ", ref ($self), " connection $self->{peer_address} (", $self->{socket}->fileno,")";
}

sub on_data {
	my ($self, $mir) = @_;
	warn "unimplemented on_data in ", ref ($self);
}

sub on_disconnect {
	my ($self, $mir) = @_;
	warn "disconnected " . ref ($self) . " connection $self->{peer_address} (", $self->{socket}->fileno,")";
}

sub print {
	my ($self, $msg) = @_;
	my $wrote = $self->{socket}->print($msg);
	unless ($wrote) {
		warn "may have just got a sigpipe: $?, $!";#, $SSL_ERROR;
	}
	return $wrote
}

# sub print {
# 	my ($self, $msg) = @_;
# 	say "debug: ", unpack 'H*', $msg;
# 	# my $write_count = 0;
# 	my $wrote = 0;
# 	do {
# 		my $wrote_more = $self->{socket}->print(substr $msg, $wrote);
# 		say "debug $wrote_more";
# 		unless ($wrote_more) {
# 			warn "may have just got a sigpipe: $?, $!";#, $SSL_ERROR;
# 			return $wrote
# 		}
# 		$wrote += $wrote_more;
# 		# $write_count++;
# 	} while ($wrote < length $msg);
# 	return $wrote
# }

1;
