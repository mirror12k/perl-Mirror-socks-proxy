package Mirror::Reflective::ClientConnection;
use parent 'Mirror::Reflective::ServiceConnection';
use strict;
use warnings;

use feature 'say';

use IO::Select;
use Iron::TCP;
use IO::Socket::INET;



sub on_data {
	my ($self, $mir) = @_;

	if ($self->{is_handshake_complete}) {
		$self->SUPER::on_data($mir);
	} elsif ($self->{buffer} =~ /\A(.)(.)(.{2})(.{4})([^\0]*\0)/s) {
		my ($socks_version, $command_code, $port, $ip) = ($1, $2, $3, $4);
		$socks_version = ord $socks_version;
		$command_code = ord $command_code;
		$ip = join '.', map ord, split '', $ip;
		$port = unpack 'n', $port;

		return $mir->disconnect_connection($self) unless $socks_version == 4;
		return $mir->disconnect_connection($self) unless $command_code == 1;

		my $hostport;
		if ($ip eq '0.0.0.1') {
			if ($self->{buffer} =~ /\A(.)(.)(.{2})(.{4})([^\0]*\0)([^\0]*)\0/) {
				$hostport = "$6:$port";
				$self->{buffer} = $';
				$self->{is_socks4a_connection} = 1;
			} else {
				warn "invalid socks4a message from $self->{peer_address}";
				return $mir->disconnect_connection($self);
			}
		} else {
			$hostport = "$ip:$port";
			$self->{buffer} = $';
		}

		my $connection = Iron::TCP->new(hostport => $hostport);
		if ($connection and $connection->connected) {
			say "socks connected $hostport";
			$self->{socket}->print("\0\x5a\0\0\0\0\0\0");
			$self->{is_handshake_complete} = 1;
			$self->{paired_connection} = Mirror::Reflective::ServiceConnection->new($connection->{sock}, is_service_connection => 1, paired_connection => $self);

			$mir->new_connection($self->{paired_connection});

			# tail call on_data if the client sent more data than just the header
			if (length $self->{buffer}) {
				say "looping ondata";
				$mir->on_data($self->{socket});
			}
		} else {
			$self->{socket}->print("\0\x5b\0\0\0\0\0\0");
			return $mir->disconnect_connection($self);
		}
	} else {
		warn "invalid client handshake from $self->{peer_address}";
		return $mir->disconnect_connection($self);
	}
}

1;
