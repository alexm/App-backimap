package App::backimap::Utils;
# ABSTRACT: backimap utilities

use strict;
use warnings;

use Exporter qw( import );

use URI::imap  ();
use URI::imaps ();

our @EXPORT_OK = qw( imap_uri_split );

=func imap_uri_split

This function takes an L<URI::imap> or L<URI::imaps> object
and returns its information on a hash reference with these keys
(undefined values may occur):

=for :list
* host
* port
* secure
* user
* password
* path

It raises an exception otherwise.

=cut

sub imap_uri_split {
    my ($uri) = @_;

    die "not an imap uri\n"
        unless ref $uri &&
            ( $uri->isa('URI::imap') || $uri->isa('URI::imaps') );

    my ( $user, $password );
    ( $user, $password ) = split /:/, $uri->userinfo
        if defined $uri->userinfo;

    return {
        host     => $uri->host,
        port     => $uri->port,
        secure   => $uri->secure,
        user     => $user,
        password => $password,
        path     => $uri->path,
    };
}

# FIXME: URI::imaps does not override secure method with a true value
#        https://rt.cpan.org/Ticket/Display.html?id=65679
package URI::imaps;

sub secure { 1 }

1;
