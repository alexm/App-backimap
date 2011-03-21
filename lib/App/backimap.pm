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
use App::backimap::Storage;

has status => (
    is => 'rw',
    isa => 'App::backimap::Status',
);

has imap => (
    is => 'rw',
    isa => 'App::backimap::IMAP',
);

has storage => (
    is => 'rw',
    isa => 'App::backimap::Storage',
);

use Getopt::Long         qw( GetOptionsFromArray );
use Pod::Usage;
use URI;
use Path::Class qw( dir file );
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
        dir     => dir( File::HomeDir->my_home, ".backimap" )->stringify(),
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

    # make sure that dir is a Path::Class
    $opt{'dir'} = dir( $opt{'dir'} );

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
    my $filename = $dir->file("backimap.json");

    $self->storage(
        App::backimap::Storage->new(
            dir => $dir,
            init => $self->{'init'},
        ),
    );

    # save initial status
    $self->save()
        if $self->{'init'};

    my $status = App::backimap::Status->load("$filename");

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

    croak "must define status first"
        unless defined $self->status;

    $self->status->store( $self->{'dir'}->file("backimap.json")->stringify() );
    $self->storage->put("save status");
}

=method backup

Perform IMAP folder backup recursively into Git repository.

=cut

sub backup {
    my ($self) = @_;

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

        $imap->examine($folder);
        for my $msg ( $imap->messages ) {
            my $file = file( $folder, $msg );
            next if $self->storage->get("$file");

            my $fetch = $imap->fetch( $msg, 'RFC822' );
            $self->storage->put( "save message $file", "$file" => $fetch->[2] );
        }

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
