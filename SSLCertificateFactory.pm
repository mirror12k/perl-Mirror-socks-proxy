package SSLCertificateFactory;
use strict;
use warnings;

use feature 'say';

use Carp;

use Digest::SHA 'sha256_hex';

use Sugar::IO::File;



sub new {
	my ($class, %args) = @_;
	my $self = bless {}, $class;

	$self->{certificate_directory} = $args{certificate_directory} // 'ssl_factory';
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

	my $hash = sha256_hex ($name);

	my $cnf = Sugar::IO::File->new("$self->{certificate_directory}/$hash.cnf");
	$cnf->write("
basicConstraints = CA:FALSE
subjectAltName          = \@alternate_names
extendedKeyUsage =serverAuth
[ alternate_names ]
DNS.1       = $name
");
	my $certificate_file = "$self->{certificate_directory}/$hash.pem";

	my $d = $self->{certificate_directory};
	my $serial = time * int rand 1000000;
	say "creating certificate for $name with serial $serial ($hash)";
	`openssl x509 -req -sha256 -days 30 -in $d/example.csr -CAkey $d/rootkey.pem -CA $d/root.pem -set_serial $serial -out $certificate_file -extfile $cnf`;

	$self->{existing_certificates}{$name} = $certificate_file;

	return $certificate_file
}

1;
