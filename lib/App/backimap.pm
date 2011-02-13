package App::backimap;
# ABSTRACT: backups imap mail

use Modern::Perl;

use URI;
use App::backimap::Utils qw( imap_uri_split );
use Data::Dump           qw( dump );

sub new {
    my ( $class, @argv ) = @_;

    my %opt;
    $opt{args} = \@argv;

    return bless \%opt, $class;
}

sub run {
    my ($self) = @_;

    my ($str) = @{ $self->{args} };

    my $uri = URI->new($str);
    dump imap_uri_split($uri);
}

1;
