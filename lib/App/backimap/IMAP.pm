package App::backimap::IMAP;
# ABSTRACT: manages IMAP connections

use Moose;
use Moose::Util::TypeConstraints;
use IO::Prompt();
use Mail::IMAPClient();
use Encode::IMAPUTF7();
use Encode();
use URI::Escape();

=attr uri

An L<URI::imap> or L<URI::imaps> object with the details
to establish an IMAP connection. Password is optional but
a prompt will ask for it if not provided.

=cut

subtype 'URI::imap'  => as Object => where { $_->isa('URI::imap')  };
subtype 'URI::imaps' => as Object => where { $_->isa('URI::imaps') };

has uri => (
    is => 'ro',
    isa => 'URI::imap | URI::imaps',
    required => 1,
);

=attr host

Host name of the IMAP server.

(This attribute is derived from C<uri> above.)

=cut

has host => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    default => sub { return shift->uri->host },
);

=attr port

Port number of the IMAP server.

(This attribue is derived from C<uri> above.)

=cut

has port => (
    is => 'ro',
    isa => 'Int',
    lazy => 1,
    default => sub { return shift->uri->port },
);

=attr secure

Boolean describing whether the connection is secure.

(This attribute is derived from C<uri> above.)

=cut

has secure => (
    is => 'ro',
    isa => 'Bool',
    lazy => 1,
    default => sub { return shift->uri->secure },
);

=attr user

User name used to login on the IMAP server.

(This attribute is derived from C<uri> above.)

=cut

has user => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    default => sub { return ( split /:/, shift->uri->userinfo )[0] },
);

=attr password

The password the user has to provide to login on the IMAP server.
If password is not provided either in the C<uri> or as an
argument to the constructor, a prompt will be shown in order to
provide it.

(This attribute can be derived from C<uri> above, if provided.)

=cut

has password => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    default => sub {
        my $self = shift;

        my $password = ( split /:/, $self->uri->userinfo )[1];
        # note that return value must be stringified, hence the .= op
        $password .= IO::Prompt::prompt( 'Password: ', -te => '*' )
            unless defined $password;

        return $password;
    },
);

=attr path

Path name to select from the IMAP server. If not provided
all the IMAP folders will be selected recursively.

=cut

has path => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    builder => '_build_path',
);

sub _build_path {
    my $self = shift;

    my $uri_path = URI::Escape::uri_unescape( $self->uri->path );
    my $utf8_path = Encode::decode( 'utf-8', $uri_path );
    my $imap_path = Encode::encode( 'imap-utf-7', $utf8_path );
    $imap_path =~ s#^/+##;

    return $imap_path;
}

=attr client

IMAP client connection.

=cut

subtype 'App::backimap::Types::Authenticated'
    => as 'Mail::IMAPClient'
    => where { $_->IsAuthenticated }
    => message { 'Could not authenticate to IMAP server.'  };

has client => (
    is => 'ro',
    isa => 'App::backimap::Types::Authenticated',
    lazy => 1,
    default => sub {
        my $self = shift;

        require IO::Socket::SSL
            if $self->secure;

        my $client = Mail::IMAPClient->new(
            Server   => $self->host,
            Port     => $self->port,
            Ssl      => $self->secure,
            User     => $self->user,
            Password => $self->password,

            # enable imap uid per folder
            Uid => 1,
        );

        return $client;
    },
);

# FIXME: URI::imaps does not override secure method with a true value
#        https://rt.cpan.org/Ticket/Display.html?id=65679
package URI::imaps;

sub secure { 1 }

1;
