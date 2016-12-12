#!/usr/bin/env perl
package Mirror::Reflective;
use strict;
use warnings;

use feature 'say';

use IO::Select;
use Iron::TCP;
use IO::Socket::INET;



sub new {
	my ($class, %args) = @_;
	my $self = bless {}, $class;

	$self->{port} = $args{port} // 3210;


	return $self
}

sub start {
	my ($self) = @_;

	$self->{server_socket} = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalPort => $self->{port},
		Listen => SOMAXCONN,
		Reuse => 1,
		Blocking => 0,
	) or die "ERROR: failed to set up listening socket: $!";

	$self->{running} = 1;


	$self->{selector} = IO::Select->new($self->{server_socket});
	while ($self->{running}) {
		while (my @ready = $self->{selector}->can_read) {
			foreach my $socket (@ready) {
				if ($socket == $self->{server_socket}) {
					my $new_socket = $socket->accept;
					$new_socket->blocking(0);
					$self->on_connect($new_socket);
					$self->{selector}->add($new_socket);
				} elsif (eof $socket) {
					$self->on_disconnect($socket);
					$self->{selector}->remove($socket);
				} else {
					$self->on_data($socket);
				}
			}
		}
	}
}

sub on_connect {
	my ($self, $socket) = @_;

	my $peer_ip = join '.', map ord, split '', $socket->peeraddr;
	my $peer_port = $socket->peerport;
	say "connection from $peer_ip:$peer_port";
}

sub on_data {
	my ($self, $socket) = @_;

	read $socket, my $buffer, 4096;
	say "got data from $socket: ", $buffer;
}

sub on_disconnect {
	my ($self, $socket) = @_;

	say "dead socket $socket";
}


sub main {
	Mirror::Reflective->new->start
}

caller or main(@ARGV);
