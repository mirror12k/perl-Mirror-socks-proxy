#!/usr/bin/env perl
package Mirror::DarkWorld;
use parent 'Mirror::Enchanted';
use strict;
use warnings;

use feature 'say';

use Gzip::Faster;

use Sugar::IO::File;
use JSON;



=pod

=head1 Mirror::DarkWorld

an intercepting proxy which constructs a 'dark-world' where only allowed domains are visible.
allows for easy mocking of sites, redirecting sites to other sites, and overriding specific file paths.
run by typing C<./Mirror/DarkWorld.pm my-config.json>

=head1 Example Configs:

=head2 block everything
	{}

=head2 allow everything
	{
		"*": { "action": "allow" }
	}

=head2 allow everything but block google.com and any subdomains
	{
		"google.com:*": { "action": "block" },
		"*.google.com:*": { "action": "block" },
		"*": { "action": "allow" }
	}

=head2 mock all requests to example.org to present a js file
	{
		"example.org:*": { "action": "mock", "content_file":"code.js" }
	}

=head2 redirect requests to www.google.com to go to example.org
	{
		"www.google.com:*": { "action": "redirect", "location":"example.org:*" }
	}

=head2 intercept a specific file of www.google.com and replace it with our own
	{
		"www.google.com:*": { "action": "allow", "path":{"/myfile.js":{ "content_file":"code.js" }} }
	}



=head2 Mirror::DarkWorld->new(%args)

specify a world_description for the world config.

=cut

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{world_description} = $args{world_description} // die "missing world_description argument";

	return $self
}

sub get_hostport_directive {
	my ($self, $hostport) = @_;

	my ($host, $port) = split ':', $hostport;

	my @possible_hosts;
	while ($host ne '*') {
		push @possible_hosts, $host;
		$host =~ s/\A(\*\.)?[^\.]*(\.?)/\*$2/s;
	}

	foreach my $possible_host (@possible_hosts) {
		# say "trying possible_host: $possible_host";
		if (exists $self->{world_description}{"$possible_host:$port"}) {
			return $self->{world_description}{"$possible_host:$port"};
		} elsif (exists $self->{world_description}{"$possible_host:*"}) {
			return $self->{world_description}{"$possible_host:*"};
		}
	}

	if (exists $self->{world_description}{"*:$port"}) {
		return $self->{world_description}{"*:$port"};
	} elsif (exists $self->{world_description}{'*'}) {
		return $self->{world_description}{'*'};
	}

	return {
		action => 'block',
	};
}

sub on_socks4_handshake {
	my ($self, $con, $hostport) = @_;

	my $action = $self->get_hostport_directive($hostport);
	if ($action->{action} eq 'allow') {
		return $self->SUPER::on_socks4_handshake($con, $hostport);

	} elsif ($action->{action} eq 'redirect') {
		die "missing location field on redirect action for '$hostport'"
				unless exists $action->{location};
		my ($host, $port) = split ':', $hostport;
		my ($location_host, $location_port) = split ':', $action->{location};
		$location_port = $port if $location_port eq '*';
		my $location = "$location_host:$location_port";
		say "redirecting $hostport connection to $location";
		return $location;

	} elsif ($action->{action} eq 'mock') {
		return undef;
	} elsif ($action->{action} eq 'block') {
		return undef;
	} else {
		die "invalid action for '$hostport' : $action->{action}";
	}
}

sub generate_mock_response {
	my ($self, $action) = @_;

	my $data;
	if (exists $action->{content_file}) {
		$data = Sugar::IO::File->new($action->{content_file})->read;
	} elsif (exists $action->{content}) {
		$data = $action->{content};
	} else {
		$data = '';
	}

	my $res = HTTP::Response->new($action->{status_code} // '200', 'OK');
	$res->protocol('HTTP/1.1');
	$res->content($data);
	$res->header('content-length' => length $res->content);

	$res->header('content-type' => 'text/plain');
	$res->header('content-type' => $action->{content_type})
			if exists $action->{content_type};

	return $res;
}

# override requests for our mock connections
sub on_request {
	my ($self, $con, $req) = @_;
	say "got request: ", $req->method . " $con->{requested_connection_hostport}" . $req->uri;

	my $action = $self->get_hostport_directive($con->{requested_connection_hostport});
	if ($action->{action} eq 'allow' or $action->{action} eq 'redirect') {

		if (exists $action->{path} and exists $action->{path}{$req->uri->path}) {
			# create a mock response
			return $self->generate_mock_response($action->{path}{$req->uri->path});
		} else {
			# return no response to let the native connection handle it
			return;
		}

	} elsif ($action->{action} eq 'mock') {
		# return a mock response
		if (exists $action->{path} and exists $action->{path}{$req->uri->path}) {
			# path a specific mock response
			return $self->generate_mock_response($action->{path}{$req->uri->path});
		} else {
			# return a default response
			return $self->generate_mock_response($action);
		}


	} elsif ($action->{action} eq 'block') {
		# return a fake 404 response to block the request
		my $res = HTTP::Response->new('404', 'Not Found');
		$res->protocol('HTTP/1.1');
		$res->header('content-length' => 0);
		return $res;

	} else {
		die "invalid action for '$con->{requested_connection_hostport}' : $action->{action}";
	}
}

sub main {
	my ($world_description_file) = @_;
	$SIG{PIPE} = 'IGNORE';
	__PACKAGE__->new(world_description => decode_json(Sugar::IO::File->new($world_description_file)->read))->start;
}

caller or main(@ARGV);
