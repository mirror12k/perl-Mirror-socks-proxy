package SSLCertificateFactory;
use strict;
use warnings;

use feature 'say';

use Carp;

use Sugar::IO::File;



=pod

=head1 SSLCertificateFactory

a utility for creating ssl certificates for specific domains.
requires openssl to be installed and the perl Sugar library.

=cut

=head2 SSLCertificateFactory->new(%args)

creates a new certificate factory.
requires an existing 'ssl_factory' directory (or another directory as specified by the certificate_directory argument).
requires a root_key argument as a path the the root private key.
requires a root_certificate argument as a path the the root CA certificate.
requires a certificate_key argument as a path the the certificate private key.
requires a certificate_request argument as a path the the template certificate signing request which will be configured and signed repeatedly.

=cut

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

=head2 $factory->certificate($name)

factory method to create/retrieve a certificate for a specific domain name.
if an existing certificate file isn't found, it will create one.
returns a filepath to the requested certificate.

=cut

sub certificate {
	my ($self, $name) = @_;
	croak "invalid certificate name $name" unless $name =~ /\A[a-zA-Z0-9_\-\.]+\Z/;

	# return one from cache if its found
	return $self->{existing_certificates}{$name} if exists $self->{existing_certificates}{$name};

	# otherwise create one
	return $self->create_certificate($name)
}

# internal method which creates the certificate
sub create_certificate {
	my ($self, $name) = @_;
	croak "invalid certificate name $name" unless $name =~ /\A[a-zA-Z0-9_\-\.]+\Z/;

	# write the configuration file
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
	warn "creating certificate for $name with serial $serial";
	# invoke openssl to produce it
	`openssl x509 -req -sha256 -days 30 -in $self->{certificate_request} -CAkey $self->{root_key} -CA $self->{root_certificate} -set_serial $serial -out $certificate_file -extfile $cnf`;

	# add it to cache
	$self->{existing_certificates}{$name} = $certificate_file;

	return $certificate_file
}

1;
