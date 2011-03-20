package App::backimap;
# ABSTRACT: backups imap mail

=head1 SYNOPSIS

    use App::backimap;
    App::backimap->new(@ARGV)->run();

=cut

use strict;
use warnings;

use Moose;
use App::backimap::Status;
use App::backimap::Status::Folder;
use App::backimap::IMAP;

has status => (
    is => 'rw',
    isa => 'App::backimap::Status',
);

has imap => (
    is => 'rw',
    isa => 'App::backimap::IMAP',
);

use Getopt::Long         qw( GetOptionsFromArray );
use Pod::Usage;
use URI;
use File::Spec::Functions qw( catfile );
use File::Path            qw( mkpath );
use Git::Wrapper;
use File::HomeDir;
use Carp;

=method new

Creates a new program instance with command line arguments.

=cut

sub new {
    my ( $class, @argv ) = @_;

    my %opt = (
        help    => 0,
        verbose => 0,
        dir     => catfile( File::HomeDir->my_home, ".backimap" ),
        init    => 0,
    );

    GetOptionsFromArray(
        \@argv,
        \%opt,

        'help|h',
        'verbose|v',
        'dir=s',
        'init',
    )
        or __PACKAGE__->usage();

    $opt{'args'} = \@argv;

    return bless \%opt, $class;
}

=method setup

Setups configuration and prompts for password if needed.
Then opens Git repository (initialize if asked) and
load previous status.

=cut

sub setup {
    my ( $self, $str ) = @_;

    my $uri = URI->new($str);

    $self->imap(
        App::backimap::IMAP->new( uri => $uri )
    );

    $self->status(
        App::backimap::Status->new(
            server    => $self->imap->host,
            user      => $self->imap->user,
        )
    );

    my $dir = $self->{'dir'};
    my $filename = catfile( $dir, "backimap.json" );
    my $git = Git::Wrapper->new($dir);
    $self->{'git'} = $git;

    if ( $self->{'init'} ) {
        die "directory $dir already initialized\n"
            if -f $filename || -d catfile( $dir, ".git" );

        mkpath($dir);
        $git->init();

        # save initial status in the Git repository
        $self->save();
    }

    my $status = App::backimap::Status->load($filename);

    die "imap details do not match with previous status\n"
        if $status->user ne $self->status->user ||
            $status->server ne $self->status->server;

    $self->status->folder( $status->folder )
        if $status->folder;
}

=method save

Save current status into Git repository.

=cut

sub save {
    my ($self) = @_;

    my $git = $self->{'git'};
    croak "must setup git repo first"
        unless defined $git && $git->isa('Git::Wrapper');

    croak "must define status first"
        unless defined $self->status;

    my $dir = $self->{'dir'};
    my $filename = catfile( $dir, "backimap.json" );

    $self->status->store($filename);

    $git->add($filename);
    $git->commit( { message => "save status" }, $filename );
}

=method backup

Perform IMAP folder backup recursively into Git repository.

=cut

sub backup {
    my ($self) = @_;

    my $git = $self->{'git'};
    croak "must init git repo first"
        unless defined $git && $git->isa('Git::Wrapper');

    my $imap = $self->imap->client;

    my $path = $self->imap->path;
    $path =~ s#^/+##;

    my @folder_list = $path ne '' ? $path : $imap->folders;

    print STDERR "Examining folders...\n"
        if $self->{'verbose'};

    for my $folder (@folder_list) {
        my $count  = $imap->message_count($folder);
        next unless defined $count;

        my $unseen = $imap->unseen_count($folder);

        if ( $self->status->folder ) {
            $self->status->folder->{$folder}->count($count);
            $self->status->folder->{$folder}->unseen($unseen);
        }
        else {
            my %status = (
                $folder => App::backimap::Status::Folder->new(
                    count => $count,
                    unseen => $unseen,
                ),
            );

            $self->status->folder(\%status);
        }

        print STDERR " * $folder ($unseen/$count)"
            if $self->{'verbose'};

        my $local_folder = catfile( $self->{'dir'}, $folder );
        mkpath( $local_folder );
        chdir $local_folder;

        $imap->examine($folder);
        for my $msg ( $imap->messages ) {
            next if -f $msg;

            my $fetch = $imap->fetch( $msg, 'RFC822' );

            open my $file, ">", $msg
                or die "message $msg: $!";

            print $file $fetch->[2];
            close $file;

            $git->add( catfile( $local_folder, $msg ) );
        }

        eval { $git->commit({ all => 1, message => "save messages from $folder" }) };

        print STDERR "\n"
            if $self->{'verbose'};
    }
}

=method run

Parses command line arguments and starts the program.

=cut

sub run {
    my ($self) = @_;

    my @args = @{ $self->{'args'} };
    $self->usage unless @args == 1;

    $self->setup(@args);
    $self->backup();
    $self->save();

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
