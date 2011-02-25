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
use JSON::Any;
use IO::Prompt           qw( prompt );
use Mail::IMAPClient;
use File::Spec::Functions qw( catfile );
use File::Path            qw( mkpath );
use Git::Wrapper;

=method new

Creates a new program instance with command line arguments.

=cut

sub new {
    my ( $class, @argv ) = @_;

    my %opt = (
        help    => 0,
        verbose => 0,
        dir     => "$ENV{HOME}/.backimap",
    );

    GetOptionsFromArray(
        \@argv,
        \%opt,

        'help|h',
        'verbose|v',
        'dir=s',
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

    $imap_cfg->{'password'} = prompt('Password: ', -te => '*' )
        unless defined $imap_cfg->{'password'};

    # make sure we can make a secure connection
    require IO::Socket::SSL
        if $imap_cfg->{'secure'};

    my $imap = Mail::IMAPClient->new(
        Server   => $imap_cfg->{'host'},
        Port     => $imap_cfg->{'port'},
        Ssl      => $imap_cfg->{'secure'},
        User     => $imap_cfg->{'user'},
        Password => $imap_cfg->{'password'},

        # enable imap uid per folder
        Uid => 1,
    )
        or die "cannot establish connection: $@\n";

    my $dir = $self->{'dir'};
    my $git = Git::Wrapper->new($dir);

    my $path = $imap_cfg->{'path'};
    $path =~ s#^/+##;

    my @folders = $path ne '' ? $path : $imap->folders;

    print STDERR "Examining folders...\n"
        if $self->{'verbose'};

    my %count_for;
    for my $f (@folders) {
        my $count  = $imap->message_count($f);
        next unless defined $count;

        my $unseen = $imap->unseen_count($f);
        $count_for{$f}{'count'}  = $count;
        $count_for{$f}{'unseen'} = $unseen;

        print STDERR " * $f ($unseen/$count)"
            if $self->{'verbose'};

        my $local_folder = catfile( $dir, $f );
        mkpath( $local_folder );
        chdir $local_folder;

        $imap->examine($f);
        for my $msg ( $imap->messages ) {
            next if -f $msg;

            my $fetch = $imap->fetch( $msg, 'RFC822' );

            open my $file, ">", $msg or die "message $msg: $!";
            print $file $fetch->[2];
            close $file;

            $git->add( catfile( $local_folder, $msg ) );
        }

        eval { $git->commit({ all => 1, message => "save messages from $f" }) };

        print STDERR "\n"
            if $self->{'verbose'};
    }

    $imap->logout;

    my $filename = catfile( $dir, "backimap.json" );
    open my $status, ">", $filename
        or die "cannot open $filename: $!\n";

    print $status JSON::Any->encode({
        timestamp => $^T,
        server    => $imap_cfg->{'host'},
        user      => $imap_cfg->{'user'},
        counters  => \%count_for,
    });

    close $status;

    my $spent = ( time - $^T ) / 60;
    printf STDERR "Backup took %.2f minutes.\n", $spent
        if $self->{'verbose'};
}

=method usage

Shows an usage summary.

=cut

sub usage {
    my ($self) = @_;

    pod2usage( verbose => 0, exitval => 1 );
}

1;
