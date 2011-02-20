package App::backimap;
# ABSTRACT: backups imap mail

=head1 SYNOPSIS

    use App::backimap;
    App::backimap->new(@ARGV)->run();

=cut

use strict;
use warnings;

use Getopt::Long         qw( GetOptionsFromArray );
use Pod::Usage;
use URI;
use App::backimap::Utils qw( imap_uri_split );
use Data::Dump           qw( dump );
use IO::Prompt           qw( prompt );
use Mail::IMAPClient;

=method new

Creates a new program instance with command line arguments.

=cut

sub new {
    my ( $class, @argv ) = @_;

    my %opt = (
        help => 0,
    );

    GetOptionsFromArray(
        \@argv,
        \%opt,

        'help|h',
    )
        or __PACKAGE__->usage();

    $opt{'args'} = \@argv;

    return bless \%opt, $class;
}

=method run

Parses command line arguments and starts the program.

=cut

sub run {
    my ($self) = @_;

    my @args = @{ $self->{'args'} };
    $self->usage unless @args == 1;

    my ($str) = @args;

    my $uri = URI->new($str);
    my $imap_cfg = imap_uri_split($uri);
    dump $imap_cfg;

    $imap_cfg->{'password'} = prompt('Password: ', -te => '*' )
        unless defined $imap_cfg->{'password'};

    my $imap = Mail::IMAPClient->new(
        Server   => $imap_cfg->{'host'},
        Port     => $imap_cfg->{'port'},
        Ssl      => $imap_cfg->{'secure'},
        User     => $imap_cfg->{'user'},
        Password => $imap_cfg->{'password'},

        # enable imap uid per folder
        Uid => 1,
    );

    my $path = $imap_cfg->{'path'};
    $path =~ s#^/+##;

    my @folders = $path ne '' ? $path : $imap->folders;

    my %count_for;
    for my $f (@folders) {
        my $count  = $imap->message_count($f);
        next unless defined $count;

        my $unseen = $imap->unseen_count($f);
        $count_for{$f}{'count'}  = $count;
        $count_for{$f}{'unseen'} = $unseen;
    }
    dump \%count_for;

    $imap->select("INBOX");

    my ($msg) = $imap->messages;
    if ( defined $msg ) {
        my $fetch = $imap->fetch( $msg, 'RFC822' );

        open my $file, ">", "$msg.txt" or die "message $msg: $!";
        print $file $fetch->[2];
        close $file;
    }

    $imap->logout;
}

=method usage

Shows an usage summary.

=cut

sub usage {
    my ($self) = @_;

    pod2usage( verbose => 0, exitval => 1 );
}

1;
