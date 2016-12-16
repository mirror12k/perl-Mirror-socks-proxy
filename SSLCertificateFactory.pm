package SSLCertificateFactory;
use strict;
use warnings;

use feature 'say';

use Carp;

use Sugar::IO::File;



sub new {
	my ($class, %args) = @_;
	my $self = bless {}, $class;

	$self->{certificate_directory} = $args{certificate_directory} // 'ssl_factory';
	$self->{root_key} = $args{root_key} // die "missing root_key path argument";
	$self->{root_certificate} = $args{root_certificate} // die "missing root_certificate path argument";
	$self->{certificate_key} = $args{certificate_key} // die "missing certificate_key path argument";
	$self->{certificate_request} = $args{certificate_request} // die "missing certificate_request path argument";
	$self->{existing_certificates} = {};

	return $self
}

sub certificate {
	my ($self, $name) = @_;
	croak "invalid certificate name $name" unless $name =~ /\A[a-zA-Z0-9_\-\.]+\Z/;

	return $self->{existing_certificates}{$name} if exists $self->{existing_certificates}{$name};

	return $self->create_certificate($name)
}

sub create_certificate {
	my ($self, $name) = @_;
	croak "invalid certificate name $name" unless $name =~ /\A[a-zA-Z0-9_\-\.]+\Z/;

	my $cnf = Sugar::IO::File->new("$self->{certificate_directory}/$name.cnf");
	$cnf->write("
basicConstraints = CA:FALSE
subjectAltName = \@alternate_names
extendedKeyUsage =serverAuth
[ alternate_names ]
DNS.1 = $name
");
	my $certificate_file = "$self->{certificate_directory}/$name.pem";
	my $serial = time * int rand 1000000;
	say "creating certificate for $name with serial $serial";
	`openssl x509 -req -sha256 -days 30 -in $self->{certificate_request} -CAkey $self->{root_key} -CA $self->{root_certificate} -set_serial $serial -out $certificate_file -extfile $cnf`;

	$self->{existing_certificates}{$name} = $certificate_file;

	return $certificate_file
}

1;
