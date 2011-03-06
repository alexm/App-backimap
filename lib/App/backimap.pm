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

=method config

Setups configuration and prompts for password if needed.

=cut

sub config {
    my ( $self, $str ) = @_;

    my $uri = URI->new($str);
    my $imap_cfg = imap_uri_split($uri);

    $imap_cfg->{'password'} = prompt('Password: ', -te => '*' )
        unless defined $imap_cfg->{'password'};

    $self->{'status'} = {
        timestamp => $^T,
        server    => $imap_cfg->{'host'},
        user      => $imap_cfg->{'user'},
    };

    $self->{'config'} = $imap_cfg;
}

=method login

Connects to IMAP server.

=cut

sub login {
    my ($self) = @_;

    # make sure we can make a secure connection
    require IO::Socket::SSL
        if $self->{'config'}{'secure'};

    $self->{'imap'} = Mail::IMAPClient->new(
        Server   => $self->{'config'}{'host'},
        Port     => $self->{'config'}{'port'},
        Ssl      => $self->{'config'}{'secure'},
        User     => $self->{'config'}{'user'},
        Password => $self->{'config'}{'password'},

        # enable imap uid per folder
        Uid => 1,
    )
        or die "cannot establish connection: $@\n";
}

=method logout

Disconnects from IMAP server.

=cut

sub logout {
    my ($self) = @_;

    my $imap = $self->{'imap'};
    $imap->logout()
        if defined $imap && $imap->isa('Mail::IMAPClient');
}

=method setup

Open Git repository (initialize if needed) and load status.

=cut

sub setup {
    my ($self) = @_;

    my $dir = $self->{'dir'};
    my $filename = catfile( $dir, "backimap.json" );
    my $git = Git::Wrapper->new($dir);

    if ( $self->{'init'} ) {
        die "directory $dir already initialized\n"
            if -f $filename || -d catfile( $dir, ".git" );

        $git->init();

        # save initial status in the Git repository
        $self->status();
    }

    open my $status, "<", $filename
        or die "cannot open $filename: $!\n";

    # slurp file
    my $json = do { local $/; <$status> };
    close $status;

    my $config = JSON::Any->decode($json);

    die "imap details do not match with previous status\n"
        if $config->{'user'} ne $self->{'status'}{'user'} ||
            $config->{'server'} ne $self->{'status'}{'server'};

    $self->{'git'} = $git;
}

=method status

Save current status into Git repository.

=cut

sub status {
    my ($self) = @_;

    my $git = $self->{'git'};
    croak "must setup git repo first"
        unless defined $git && $git->isa('Git::Wrapper');

    croak "must define status first"
        unless defined $self->{'status'};

    my $dir = $self->{'dir'};
    my $filename = catfile( $dir, "backimap.json" );
    open my $status, ">", $filename
        or die "cannot open $filename: $!\n";

    print $status JSON::Any->encode( $self->{'status'} );
    close $status;

    $git->add($filename);
    $git->commit( $filename, { message => "save status" } );
}

=method backup

Perform IMAP folder backup recursively into Git repository.

=cut

sub backup {
    my ($self) = @_;

    my $git = $self->{'git'};
    croak "must init git repo first"
        unless defined $git && $git->isa('Git::Wrapper');

    my $imap = $self->{'imap'};
    croak "imap connection unavailable"
        unless defined $imap && $imap->isa('Mail::IMAPClient');

    my $path = $self->{'config'}{'path'};
    $path =~ s#^/+##;

    my @folder_list = $path ne '' ? $path : $imap->folders;

    print STDERR "Examining folders...\n"
        if $self->{'verbose'};

    my %count_for;
    for my $folder (@folder_list) {
        my $count  = $imap->message_count($folder);
        next unless defined $count;

        my $unseen = $imap->unseen_count($folder);
        $count_for{$folder}{'count'}  = $count;
        $count_for{$folder}{'unseen'} = $unseen;

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

    $self->{'status'}{'counters'} = \%count_for;
}

=method run

Parses command line arguments and starts the program.

=cut

sub run {
    my ($self) = @_;

    my @args = @{ $self->{'args'} };
    $self->usage unless @args == 1;

    $self->config(@args);
    $self->setup();
    $self->login();
    $self->backup();
    $self->logout();
    $self->status();

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
