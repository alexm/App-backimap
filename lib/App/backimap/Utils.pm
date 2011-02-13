package App::backimap::Utils;
# ABSTRACT: backimap utilities

use Modern::Perl;

use Exporter qw( import );

use URI::imap  ();
use URI::imaps ();

our @EXPORT_OK = qw( imap_uri_split );

sub imap_uri_split {
    my ($uri) = @_;

    die "not an imap uri\n"
        unless ref $uri &&
            ( $uri->isa('URI::imap') || $uri->isa('URI::imaps') );

    my ( $user, $password ) = split /:/, $uri->userinfo
        if defined $uri->userinfo;

    return {
        host     => $uri->host,
        port     => $uri->port,
        secure   => $uri->secure,
        user     => $user,
        password => $password,
    };
}

# FIXME: URI::imaps does not override secure method with a true value
#        https://rt.cpan.org/Ticket/Display.html?id=65679
package URI::imaps;

sub secure { 1 }

1;
