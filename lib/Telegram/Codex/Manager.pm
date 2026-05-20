package Telegram::Codex::Manager;

use strict;
use warnings;

use Cwd qw(getcwd);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use HTTP::Request::Common qw(GET POST);
use JSON::XS qw(decode_json encode_json);
use LWP::UserAgent;
use MIME::Base64 qw(encode_base64);

sub new {
    my ( $class, %args ) = @_;
    my $cwd = $args{cwd} || getcwd();
    my $home = defined $args{home} ? $args{home} : $ENV{HOME};
    my $skill_root = defined $args{skill_root} ? $args{skill_root} : $class->_default_skill_root;
    my $self = bless {
        cwd                  => $cwd,
        home                 => $home,
        skill_root           => $skill_root,
        stdout_fh            => $args{stdout_fh} || \*STDOUT,
        stderr_fh            => $args{stderr_fh} || \*STDERR,
        env                  => {},
        get_runner           => $args{get_runner},
        post_runner          => $args{post_runner},
        download_runner      => $args{download_runner},
        listener_start_runner => $args{listener_start_runner},
        listener_start_pid   => $args{listener_start_pid},
    }, $class;
    $self->{env} = $args{env} || $self->_merged_env;
    $self->{ua} = $args{ua} || $self->_build_ua;
    return $self;
}

sub main_install          { return shift->_run_main( 'install',          @_ ) }
sub main_get_me           { return shift->_run_main( 'get_me',           @_ ) }
sub main_updates          { return shift->_run_main( 'updates',          @_ ) }
sub main_download         { return shift->_run_main( 'download',         @_ ) }
sub main_reply            { return shift->_run_main( 'reply',            @_ ) }
sub main_send_photo       { return shift->_run_main( 'send_photo',       @_ ) }
sub main_send_document    { return shift->_run_main( 'send_document',    @_ ) }
sub main_auto_reply_start { return shift->_run_main( 'auto_reply_start', @_ ) }
sub main_listen           { return shift->_run_main( 'listen',           @_ ) }
sub main_start            { return shift->_run_main( 'start',            @_ ) }

sub _run_main {
    my ( $class, $mode, @argv ) = @_;
    my $self = ref($class) ? $class : $class->new;
    my $code = eval {
        my $method = "execute_$mode";
        my $result = $self->$method(@argv);
        print { $self->{stdout_fh} } $self->encode_pretty_json($result) . "\n";
        return 0;
    };
    if ( my $error = $@ ) {
        chomp $error;
        print { $self->{stderr_fh} } "$error\n";
        return 2;
    }
    return $code;
}

sub execute_install {
    my ( $self, @argv ) = @_;
    die "Usage: dashboard telegram-codex.install <TELEGRAM_BOT_TOKEN>\n" if @argv > 1;
    my $token = $self->resolve_token( $argv[0] );
    my @targets = $self->plugin_targets;
    my @installed;
    for my $target (@targets) {
        push @installed, $self->scaffold_plugin(
            plugin_root      => $target->{plugin_root},
            marketplace_path => $target->{marketplace_path},
            token            => $token,
        );
    }
    my $codex_wrapper = $self->install_codex_launchers;
    return {
        mode      => 'install',
        plugin    => 'telegram-codex',
        installed => \@installed,
        codex_wrapper => $codex_wrapper,
    };
}

sub auto_setup {
    my ($self) = @_;
    return {
        mode          => 'auto_setup',
        codex_wrapper => $self->install_codex_launchers,
    };
}

sub execute_start {
    my ( $self, @argv ) = @_;
    my $cmd = defined $argv[0] ? $argv[0] : q{};
    my $config_path = $self->codex_config_path;
    my $config = $self->read_codex_config($config_path);
    my $ticket = $self->env_value('TICKET_REF');

    if ( $cmd eq 'add' ) {
        my $codex_session_ref = defined $argv[1] ? $argv[1] : $ticket;
        die "Missing ticket ref\n" if !defined $ticket || $ticket eq q{} || !defined $codex_session_ref || $codex_session_ref eq q{};
        $config->{$ticket} = $codex_session_ref;
        $config->{_last_action} = "Add $ticket";
        $config->{_last_update} = $self->now_string;
        $self->write_codex_config( $config_path, $config );
        return {
            mode         => 'start',
            action       => 'add',
            ticket       => $ticket,
            codex_session => $codex_session_ref,
        };
    }

    if ( $cmd eq 'remove' ) {
        die "Missing ticket ref\n" if !defined $ticket || $ticket eq q{};
        my $codex_session_ref = $config->{$ticket}
          or die "Codex Session Not Found\n";
        die "Missing ticket ref\n" if !$codex_session_ref;
        delete $config->{$codex_session_ref};
        $config->{_last_action} = "Remove $ticket";
        $config->{_last_update} = $self->now_string;
        $self->write_codex_config( $config_path, $config );
        return {
            mode         => 'start',
            action       => 'remove',
            ticket       => $ticket,
            codex_session => $codex_session_ref,
        };
    }

    my $plan = $self->codex_start_plan( $config, @argv );
    return $plan if $self->env_value('TELEGRAM_CODEX_START_CAPTURE');

    $self->start_listener_if_needed( $plan->{listener_session_id} ) if $plan->{start_listener};

    if ( my $ollama_model = $self->env_value('OLLAMA_MODEL') ) {
        my $default_model = 'qwen3.5:397b-cloud';
        if ( $ollama_model eq '2' ) {
            my $exit = system( qw(ollama launch codex --model), $default_model );
            exit( $exit == -1 ? 1 : ( $exit >> 8 ) );
        }
        $ollama_model = $default_model if $ollama_model eq '1';
        my $exit = system( qw(ollama launch codex --model), $ollama_model, '--', @{ $plan->{codex_args} } );
        exit( $exit == -1 ? 1 : ( $exit >> 8 ) );
    }

    my $exit = system { $plan->{real_codex_bin} } $plan->{real_codex_bin}, @{ $plan->{codex_args} };
    exit( $exit == -1 ? 1 : ( $exit >> 8 ) );
}

sub execute_get_me {
    my ( $self, @argv ) = @_;
    die "Usage: dashboard telegram-codex.get-me\n" if @argv;
    return $self->telegram_get('getMe')->{result};
}

sub execute_updates {
    my ( $self, @argv ) = @_;
    die "Usage: dashboard telegram-codex.updates [OFFSET] [LIMIT] [TIMEOUT]\n" if @argv > 3;
    my $result = $self->telegram_get(
        'getUpdates',
        {
            ( defined $argv[0] ? ( offset => $argv[0] ) : () ),
            ( defined $argv[1] ? ( limit  => $argv[1] ) : () ),
            ( defined $argv[2] ? ( timeout => $argv[2] ) : () ),
        }
    );
    my @updates = map { $self->summarise_update($_) } @{ $result->{result} || [] };
    return {
        count       => scalar @updates,
        updates     => \@updates,
        next_offset => @updates ? $updates[-1]{update_id} + 1 : undef,
    };
}

sub execute_download {
    my ( $self, @argv ) = @_;
    die "Usage: dashboard telegram-codex.download <FILE_ID> [TARGET_DIR] [FILENAME]\n" if !@argv || @argv > 3;
    my ( $file_id, $target_dir, $filename ) = @argv;
    my $file = $self->telegram_get( 'getFile', { file_id => $file_id } )->{result};
    my $bytes = $self->telegram_download( $file->{file_path} );
    my $dir = $target_dir || File::Spec->catdir( $self->{cwd}, 'downloads' );
    make_path($dir) if !-d $dir;
    my $name = $filename || $self->basename( $file->{file_path} );
    my $path = File::Spec->catfile( $dir, $name );
    open my $fh, '>', $path or die "Unable to write $path: $!";
    binmode $fh;
    print {$fh} $bytes;
    close $fh or die "Unable to close $path: $!";
    return {
        file_id            => $file_id,
        telegram_file_path => $file->{file_path},
        saved_to           => $path,
        bytes              => length $bytes,
    };
}

sub execute_reply {
    my ( $self, @argv ) = @_;
    die "Usage: dashboard telegram-codex.reply <CHAT_ID> <TEXT>\n" if @argv < 2;
    my $chat_id = shift @argv;
    my $text = join q{ }, @argv;
    return $self->telegram_post( 'sendMessage', { chat_id => $chat_id, text => $text } )->{result};
}

sub execute_send_photo {
    my ( $self, @argv ) = @_;
    die "Usage: dashboard telegram-codex.send-photo <CHAT_ID> <PHOTO_PATH> [CAPTION]\n" if @argv < 2;
    my $chat_id = shift @argv;
    my $photo_path = shift @argv;
    my $caption = join q{ }, @argv;
    die "Photo path does not exist: $photo_path\n" if !-f $photo_path;
    return $self->telegram_post_file(
        'sendPhoto',
        { chat_id => $chat_id, caption => $caption },
        { photo   => $photo_path },
    )->{result};
}

sub execute_send_document {
    my ( $self, @argv ) = @_;
    die "Usage: dashboard telegram-codex.send-document <CHAT_ID> <DOCUMENT_PATH> [CAPTION]\n" if @argv < 2;
    my $chat_id = shift @argv;
    my $document_path = shift @argv;
    my $caption = join q{ }, @argv;
    die "Document path does not exist: $document_path\n" if !-f $document_path;
    return $self->telegram_post_file(
        'sendDocument',
        { chat_id => $chat_id, caption => $caption },
        { document => $document_path },
    )->{result};
}

sub execute_auto_reply_start {
    my ( $self, @argv ) = @_;
    my $reply_text = @argv
      ? join( q{ }, @argv )
      : 'Talbot Telegram bridge is live. Send text, photos, or files here and ask Codex to poll and reply.';
    my $result = $self->telegram_get( 'getUpdates', { limit => 20, timeout => 0 } );
    my @replied;
    my @updates = @{ $result->{result} || [] };
    for my $update (@updates) {
        my $message = $update->{message} || $update->{edited_message} || {};
        my $text = defined $message->{text} ? $message->{text} : q{};
        next if $text ne '/start';
        my $chat_id = $message->{chat}{id};
        next if !defined $chat_id;
        my $sent = $self->telegram_post(
            'sendMessage',
            {
                chat_id             => $chat_id,
                text                => $reply_text,
                reply_to_message_id => $message->{message_id},
            }
        )->{result};
        push @replied, {
            update_id  => $update->{update_id},
            chat_id    => $chat_id,
            message_id => $sent->{message_id},
        };
    }
    if (@updates) {
        $self->telegram_get( 'getUpdates', { offset => $updates[-1]{update_id} + 1 } );
    }
    return {
        checked     => scalar @updates,
        replied     => \@replied,
        next_offset => @updates ? $updates[-1]{update_id} + 1 : undef,
    };
}

sub execute_listen {
    my ( $self, @argv ) = @_;
    die "Usage: dashboard telegram-codex.listen [MAX_CYCLES] [POLL_TIMEOUT] [REPLY_TEXT]\n" if @argv > 3;
    my $max_cycles;
    my $poll_timeout = 30;
    if ( @argv && $argv[0] =~ /\A\d+\z/ ) {
        $max_cycles = shift @argv;
    }
    if ( @argv && $argv[0] =~ /\A\d+\z/ ) {
        $poll_timeout = shift @argv;
    }
    my $reply_text = @argv
      ? join( q{ }, @argv )
      : undef;

    my $paths = $self->listener_paths;
    make_path( $paths->{runtime_dir} ) if !-d $paths->{runtime_dir};
    my $offset = $self->read_listener_offset( $paths->{offset_file} );
    if ( !defined $offset ) {
        $offset = $self->recover_listener_offset_from_inbox( $paths->{inbox_file} );
    }
    my $prime_latest = ( $self->env_value('TELEGRAM_CODEX_LISTENER_PRIME_LATEST') || q{} ) =~ /\A(?:1|true|yes|on)\z/i ? 1 : 0;
    if ( !defined $offset && $prime_latest ) {
        my $prime_offset;
        while (1) {
            my %prime_params = (
                limit   => 100,
                timeout => 0,
            );
            $prime_params{offset} = $prime_offset if defined $prime_offset;
            my $prime_result = $self->telegram_get( 'getUpdates', \%prime_params );
            my @prime_updates = @{ $prime_result->{result} || [] };
            last if !@prime_updates;
            $prime_offset = $prime_updates[-1]{update_id} + 1;
            last if @prime_updates < 100;
        }
        if ( defined $prime_offset ) {
            $offset = $prime_offset;
            $self->write_listener_offset( $paths->{offset_file}, $offset );
        }
    }
    my $cycles = 0;
    my $processed = 0;
    my $replied = 0;
    my @reply_errors;

    while (1) {
        my %params = (
            limit   => 20,
            timeout => $poll_timeout,
        );
        $params{offset} = $offset if defined $offset;
        my $result = $self->telegram_get( 'getUpdates', \%params );
        my @updates = @{ $result->{result} || [] };
        for my $update (@updates) {
            my $update_id = $update->{update_id};
            next if defined $offset && defined $update_id && $update_id < $offset;
            my $summary = $self->summarise_update($update);
            $self->append_inbox_entry( $paths->{inbox_file}, $summary );
            $processed++;
            my $message = $update->{message} || $update->{edited_message} || {};
            my $chat_id = $message->{chat}{id};
            if ( defined $reply_text && $reply_text ne q{} && defined $chat_id && $self->update_needs_listener_reply($summary) ) {
                my $sent = eval {
                    $self->telegram_post(
                        'sendMessage',
                        {
                            chat_id             => $chat_id,
                            text                => $reply_text,
                            reply_to_message_id => $message->{message_id},
                        }
                    );
                };
                if ( my $error = $@ ) {
                    chomp $error;
                    push @reply_errors, {
                        update_id  => $summary->{update_id},
                        chat_id    => $chat_id,
                        message_id => $message->{message_id},
                        error      => $error,
                    };
                }
                else {
                    $replied++;
                }
            }
        }
        if (@updates) {
            $offset = $updates[-1]{update_id} + 1;
            $self->write_listener_offset( $paths->{offset_file}, $offset );
        }
        $cycles++;
        last if defined $max_cycles && $cycles >= $max_cycles;
    }

    return {
        mode       => 'listen',
        cycles     => $cycles,
        processed  => $processed,
        replied    => $replied,
        reply_errors => \@reply_errors,
        next_offset => $offset,
        offset_file => $paths->{offset_file},
        inbox_file  => $paths->{inbox_file},
    };
}

sub plugin_targets {
    my ($self) = @_;
    my @targets;
    push @targets, {
        plugin_root      => $self->resolve_path( $self->env_value('CODEX_PRIMARY_PLUGIN_ROOT') || '~/.codex/.tmp/plugins/plugins' ),
        marketplace_path => $self->resolve_path( $self->env_value('CODEX_PRIMARY_MARKETPLACE_PATH') || '~/.codex/.tmp/plugins/.agents/plugins/marketplace.json' ),
    };

    my $mirror_marketplace = $self->env_value('CODEX_MIRROR_MARKETPLACE_PATH') || '~/_codex/michael/.tmp/plugins/.agents/plugins/marketplace.json';
    my $mirror_plugin_root = $self->env_value('CODEX_MIRROR_PLUGIN_ROOT') || '~/_codex/michael/.tmp/plugins/plugins';
    my $resolved_mirror_marketplace = $self->resolve_path($mirror_marketplace);
    if ( -f $resolved_mirror_marketplace || -d dirname($resolved_mirror_marketplace) ) {
        push @targets, {
            plugin_root      => $self->resolve_path($mirror_plugin_root),
            marketplace_path => $resolved_mirror_marketplace,
        };
    }
    return @targets;
}

sub install_codex_launchers {
    my ($self) = @_;
    my $paths = $self->codex_launcher_paths;
    my $real_codex_path = $self->resolve_real_codex_bin($paths);
    $self->write_text_file( $paths->{real_bin_file}, $real_codex_path . "\n" );
    my $dashboard_script = $self->dashboard_codex_launcher_script(
        real_codex_path => $real_codex_path,
        real_bin_file   => $paths->{real_bin_file},
    );
    $self->write_text_file( $paths->{dashboard_launcher_path}, $dashboard_script );
    chmod 0700, $paths->{dashboard_launcher_path};
    my $wrapper_script = $self->codex_handoff_wrapper_script(
        dashboard_launcher_path => $paths->{dashboard_launcher_path},
    );
    $self->write_text_file( $paths->{wrapper_path}, $wrapper_script );
    chmod 0700, $paths->{wrapper_path};
    return {
        wrapper_path            => $paths->{wrapper_path},
        dashboard_launcher_path => $paths->{dashboard_launcher_path},
        real_codex_path         => $real_codex_path,
        real_bin_file           => $paths->{real_bin_file},
    };
}

sub scaffold_plugin {
    my ( $self, %args ) = @_;
    my $plugin_root = $args{plugin_root};
    my $marketplace_path = $args{marketplace_path};
    my $token = $args{token};
    my $plugin_dir = File::Spec->catdir( $plugin_root, 'telegram-codex' );
    my $codex_plugin_dir = File::Spec->catdir( $plugin_dir, '.codex-plugin' );
    my $scripts_dir = File::Spec->catdir( $plugin_dir, 'scripts' );
    make_path($codex_plugin_dir);
    make_path($scripts_dir);
    make_path( dirname($marketplace_path) );

    $self->write_text_file(
        File::Spec->catfile( $codex_plugin_dir, 'plugin.json' ),
        $self->encode_pretty_json( $self->plugin_manifest ),
    );
    $self->write_text_file(
        File::Spec->catfile( $plugin_dir, '.mcp.json' ),
        $self->encode_pretty_json( $self->plugin_mcp_config ),
    );
    $self->write_text_file(
        File::Spec->catfile( $plugin_dir, '.env' ),
        'TELEGRAM_BOT_TOKEN=' . $token . "\n",
    );
    $self->write_text_file(
        File::Spec->catfile( $plugin_dir, 'README.md' ),
        $self->plugin_readme,
    );
    my $script_path = File::Spec->catfile( $scripts_dir, 'telegram_mcp.py' );
    $self->write_text_file( $script_path, $self->plugin_script_python );
    chmod 0700, $script_path;
    $self->update_marketplace($marketplace_path);
    return {
        plugin_dir       => $plugin_dir,
        marketplace_path => $marketplace_path,
        script_path      => $script_path,
    };
}

sub plugin_manifest {
    return {
        name        => 'telegram-codex',
        version     => '0.2.0',
        description => 'Local Codex Telegram MCP bridge installed by the telegram-codex DD skill.',
        author      => { name => 'Michael Vu' },
        homepage    => 'https://telegram.org/',
        license     => 'MIT',
        keywords    => [ 'telegram', 'codex', 'mcp', 'bot' ],
        mcpServers  => './.mcp.json',
        interface   => {
            displayName      => 'Telegram Codex',
            shortDescription => 'Poll, reply, and keep a Telegram listener active',
            longDescription  => 'Use a local Telegram Bot API bridge for Codex through a generated stdio MCP server and a governed always-on listener command.',
            developerName    => 'Michael Vu',
            category         => 'Productivity',
            capabilities     => [ 'Interactive', 'Write' ],
            websiteURL       => 'https://telegram.org/',
            privacyPolicyURL => 'https://telegram.org/privacy',
            termsOfServiceURL => 'https://telegram.org/tos',
            defaultPrompt    => [ 'Check Telegram updates, download files, and send replies through the generated local bridge' ],
            brandColor       => '#229ED9',
            screenshots      => [],
        },
    };
}

sub plugin_mcp_config {
    return {
        mcpServers => {
            'telegram-codex-bot' => {
                type    => 'stdio',
                command => 'python3',
                args    => [ './scripts/telegram_mcp.py' ],
                note    => 'Local Telegram Bot API MCP bridge generated by the telegram-codex DD skill.',
            },
        },
    };
}

sub plugin_readme {
    return <<'EOF';
# Telegram Codex Plugin

This local Codex plugin exposes a Telegram Bot API bridge over MCP.

Current mode:

- polling-first inbox access
- send text replies
- send photos
- send documents
- download incoming Telegram files locally
- auto-reply to `/start`

The bot token is loaded from the plugin-local `.env` file.

For immediate bot replies outside manual Codex polling, run the skill listener:

- `dashboard telegram-codex.listen`

After `dashboard skills install telegram-codex`, the managed launch chain is:

- `codex`
- `~/.developer-dashboard/cli/codex`
- `dashboard telegram-codex.start`
EOF
}

sub codex_config_path {
    my ($self) = @_;
    return File::Spec->catfile( $self->resolve_path('~/.developer-dashboard/config'), 'codex.json' );
}

sub read_codex_config {
    my ( $self, $path ) = @_;
    return {} if !-f $path;
    return decode_json( $self->read_text_file($path) );
}

sub write_codex_config {
    my ( $self, $path, $data ) = @_;
    $self->write_text_file( $path, $self->encode_pretty_json($data) );
    return $path;
}

sub now_string {
    my ($self) = @_;
    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime;
    return sprintf(
        "%04d-%02d-%02d %02d:%02d:%02d",
        $year + 1900,
        $mon + 1, $mday, $hour, $min, $sec
    );
}

sub codex_start_plan {
    my ( $self, $config, @argv ) = @_;
    my $ticket = $self->env_value('TICKET_REF');
    my @codex_args = @argv;
    my $mapped_session = defined $ticket && $ticket ne q{} ? $config->{$ticket} : undef;
    if ( defined $mapped_session && $mapped_session ne q{} ) {
        @codex_args = ( 'resume', $mapped_session, @argv );
    }
    my $listener_session_id = $self->env_value('TELEGRAM_CODEX_SESSION_ID')
      || $mapped_session
      || $self->env_value('CODEX_SESSION_ID')
      || 'default';
    return {
        mode                => 'start',
        action              => 'exec',
        ticket              => $ticket,
        mapped_session      => $mapped_session,
        codex_args          => \@codex_args,
        real_codex_bin      => $self->resolve_real_codex_bin( $self->codex_launcher_paths ),
        start_listener      => ( $self->env_value('TELEGRAM_BOT_TOKEN') && ( $self->env_value('TELEGRAM_CODEX_ENABLE_AUTOSTART') || q{} ) eq '1' ) ? 1 : 0,
        listener_session_id => $listener_session_id,
    };
}

sub start_listener_if_needed {
    my ( $self, $session_id ) = @_;
    my $paths = $self->listener_paths_for_session($session_id);
    make_path( $paths->{runtime_dir} ) if !-d $paths->{runtime_dir};
    if ( -f $paths->{pid_file} ) {
        my $existing_pid = $self->read_text_file( $paths->{pid_file} );
        $existing_pid =~ s/\s+\z//;
        if ( $existing_pid ne q{} && kill 0, $existing_pid ) {
            return {
                listener_running   => 1,
                listener_session_id => $session_id,
                %{$paths},
            };
        }
        unlink $paths->{pid_file};
    }

    if ( $self->{listener_start_runner} ) {
        my $pid = defined $self->{listener_start_pid} ? $self->{listener_start_pid} : $$;
        $self->{listener_start_runner}->( $session_id, $paths );
        $self->write_text_file( $paths->{pid_file}, "$pid\n" );
        return {
            listener_running    => 0,
            listener_session_id => $session_id,
            pid                 => $pid,
            %{$paths},
        };
    }

    my $pid = fork();
    die "Unable to fork telegram listener: $!" if !defined $pid;
    if ( $pid == 0 ) {
        open STDIN,  '<', '/dev/null'         or die "Unable to reopen stdin: $!";  # uncoverable statement
        open STDOUT, '>>', $paths->{log_file} or die "Unable to reopen stdout: $!"; # uncoverable statement
        open STDERR, '>>', $paths->{log_file} or die "Unable to reopen stderr: $!"; # uncoverable statement
        $ENV{TELEGRAM_CODEX_SESSION_ID} = $session_id;
        $ENV{TELEGRAM_CODEX_LISTENER_PRIME_LATEST} = 1;
        my $exit = system( 'dashboard', 'telegram-codex.listen' );
        exit( $exit == -1 ? 1 : ( $exit >> 8 ) );
    }

    $self->write_text_file( $paths->{pid_file}, "$pid\n" );
    return {
        listener_running   => 0,
        listener_session_id => $session_id,
        pid                => $pid,
        %{$paths},
    };
}

sub plugin_script_python {
    my ($self) = @_;
    return $self->read_text_file( $self->plugin_script_source_path );
}

sub plugin_script_source_path {
    my ($self) = @_;
    return File::Spec->catfile( $self->{skill_root}, 'scripts', 'telegram_mcp.py' );
}

sub codex_launcher_paths {
    my ($self) = @_;
    my $wrapper_dir = $self->select_codex_wrapper_dir;
    my $runtime_root = $self->resolve_path('~/.telegram-codex');
    my $dashboard_cli_root = $self->resolve_path('~/.developer-dashboard/cli');
    return {
        wrapper_dir             => $wrapper_dir,
        wrapper_path            => File::Spec->catfile( $wrapper_dir, 'codex' ),
        dashboard_cli_root      => $dashboard_cli_root,
        dashboard_launcher_path => File::Spec->catfile( $dashboard_cli_root, 'codex' ),
        real_bin_file           => File::Spec->catfile( $runtime_root, '.codex-real-bin' ),
    };
}

sub select_codex_wrapper_dir {
    my ($self) = @_;
    my @preferred = map { $self->resolve_path($_) } qw(~/.local/bin ~/bin);
    my %preferred = map { $_ => 1 } @preferred;
    my @path_entries = split /:/, ( $self->env_value('PATH') || $ENV{PATH} || q{} );
    my %seen;
    my @ordered = grep { defined $_ && $_ ne q{} && !$seen{$_}++ } map { $self->resolve_path($_) } @path_entries;
    my @candidates = grep { $preferred{$_} } @ordered;
    push @candidates, grep { !$seen{$_}++ } @preferred;

    for my $dir (@candidates) {
        my $path = File::Spec->catfile( $dir, 'codex' );
        next if !-f $path;
        my $content = eval { $self->read_text_file($path) };
        next if $@;
        return $dir if $content =~ /telegram-codex-managed-codex-wrapper/;
    }

    for my $dir (@candidates) {
        my $path = File::Spec->catfile( $dir, 'codex' );
        return $dir if !-e $path;
    }

    return $candidates[0];
}

sub resolve_real_codex_bin {
    my ( $self, $paths ) = @_;
    my $explicit = $self->env_value('CODEX_REAL_BIN');
    return $explicit if defined $explicit && $explicit ne q{};

    my $detected = qx{command -v codex 2>/dev/null};
    chomp $detected;
    my %skip = map { $_ => 1 } grep { defined $_ && $_ ne q{} } ( $paths->{wrapper_path}, $paths->{dashboard_launcher_path} );
    if ( defined $detected && $detected ne q{} && !$skip{$detected} ) {
        return $detected;
    }
    if ( -f $paths->{real_bin_file} ) {
        my $stored = $self->read_text_file( $paths->{real_bin_file} );
        $stored =~ s/\s+\z//;
        return $stored if $stored ne q{};
    }
    die "Unable to resolve the real codex binary path\n";
}

sub dashboard_codex_launcher_script {
    my ( $self, %args ) = @_;
    return <<"EOF";
#!/bin/sh
# telegram-codex-managed-dashboard-codex-launcher
set -eu
exec dashboard telegram-codex.start "\$@"
EOF
}

sub codex_handoff_wrapper_script {
    my ( $self, %args ) = @_;
    my $dashboard_launcher_path = $args{dashboard_launcher_path};
    return <<"EOF";
#!/bin/sh
# telegram-codex-managed-codex-wrapper
set -eu
exec "$dashboard_launcher_path" "\$@"
EOF
}

sub update_marketplace {
    my ( $self, $path ) = @_;
    my $data;
    if ( -f $path ) {
        $data = decode_json( $self->read_text_file($path) );
    }
    else {
        $data = {
            name      => 'local-plugins',
            interface => { displayName => 'Local plugins' },
            plugins   => [],
        };
    }
    my $entry = {
        name   => 'telegram-codex',
        source => {
            source => 'local',
            path   => './plugins/telegram-codex',
        },
        policy => {
            installation  => 'AVAILABLE',
            authentication => 'ON_INSTALL',
        },
        category => 'Productivity',
    };
    my $found = 0;
    for my $plugin ( @{ $data->{plugins} } ) {
        next if $plugin->{name} ne 'telegram-codex';
        %{$plugin} = %{$entry};
        $found = 1;
    }
    push @{ $data->{plugins} }, $entry if !$found;
    $self->write_text_file( $path, $self->encode_pretty_json($data) );
}

sub summarise_update {
    my ( $self, $update ) = @_;
    my $message = $update->{message} || $update->{edited_message} || {};
    my $chat = $message->{chat} || {};
    my $photos = $message->{photo} || [];
    my $best_photo = @{$photos} ? $photos->[-1] : undef;
    return {
        update_id  => $update->{update_id},
        message_id => $message->{message_id},
        date       => $message->{date},
        chat       => {
            id         => $chat->{id},
            type       => $chat->{type},
            title      => $chat->{title},
            username   => $chat->{username},
            first_name => $chat->{first_name},
            last_name  => $chat->{last_name},
        },
        from     => $message->{from},
        text     => $message->{text},
        caption  => $message->{caption},
        photo    => $best_photo,
        document => $message->{document},
        audio    => $message->{audio},
        video    => $message->{video},
        voice    => $message->{voice},
    };
}

sub telegram_get {
    my ( $self, $method, $params ) = @_;
    if ( $self->{get_runner} ) {
        return $self->{get_runner}->( $method, $params || {} );
    }
    my $url = $self->telegram_api_base . '/' . $method;
    my $request = GET( $url, %{ $params || {} } );
    my $response = $self->{ua}->request($request);
    die "Telegram GET failed for $method: " . $response->status_line . "\n" if !$response->is_success;
    my $payload = decode_json( $response->decoded_content );
    die "Telegram GET failed for $method: " . encode_json($payload) . "\n" if !$payload->{ok};
    return $payload;
}

sub telegram_post {
    my ( $self, $method, $params ) = @_;
    if ( $self->{post_runner} ) {
        return $self->{post_runner}->( $method, $params || {}, {} );
    }
    my $url = $self->telegram_api_base . '/' . $method;
    my $request = POST( $url, Content => [ %{ $params || {} } ] );
    my $response = $self->{ua}->request($request);
    die "Telegram POST failed for $method: " . $response->status_line . "\n" if !$response->is_success;
    my $payload = decode_json( $response->decoded_content );
    die "Telegram POST failed for $method: " . encode_json($payload) . "\n" if !$payload->{ok};
    return $payload;
}

sub telegram_post_file {
    my ( $self, $method, $params, $files ) = @_;
    if ( $self->{post_runner} ) {
        return $self->{post_runner}->( $method, $params || {}, $files || {} );
    }
    my @content;
    for my $key ( sort keys %{ $params || {} } ) {
        push @content, $key => $params->{$key};
    }
    for my $key ( sort keys %{ $files || {} } ) {
        push @content, $key => [ $files->{$key} ];
    }
    my $url = $self->telegram_api_base . '/' . $method;
    my $request = POST( $url, Content_Type => 'form-data', Content => \@content );
    my $response = $self->{ua}->request($request);
    die "Telegram POST failed for $method: " . $response->status_line . "\n" if !$response->is_success;
    my $payload = decode_json( $response->decoded_content );
    die "Telegram POST failed for $method: " . encode_json($payload) . "\n" if !$payload->{ok};
    return $payload;
}

sub telegram_download {
    my ( $self, $file_path ) = @_;
    if ( $self->{download_runner} ) {
        return $self->{download_runner}->( $self->telegram_file_base . '/' . $file_path );
    }
    my $response = $self->{ua}->get( $self->telegram_file_base . '/' . $file_path );
    die "Telegram download failed for $file_path: " . $response->status_line . "\n" if !$response->is_success;
    return $response->decoded_content( charset => 'none' );
}

sub telegram_api_base {
    my ($self) = @_;
    return 'https://api.telegram.org/bot' . $self->resolve_token;
}

sub telegram_file_base {
    my ($self) = @_;
    return 'https://api.telegram.org/file/bot' . $self->resolve_token;
}

sub listener_paths {
    my ($self) = @_;
    return $self->listener_paths_for_session( $self->listener_session_id );
}

sub listener_paths_for_session {
    my ( $self, $session_id ) = @_;
    my $runtime_root = $self->resolve_path( $self->env_value('TELEGRAM_CODEX_RUNTIME_DIR') || '~/.telegram-codex' );
    my $runtime_dir = File::Spec->catdir( $runtime_root, $self->normalise_session_id($session_id) );
    return {
        runtime_root => $runtime_root,
        runtime_dir  => $runtime_dir,
        offset_file  => File::Spec->catfile( $runtime_dir, 'listener.offset' ),
        inbox_file   => File::Spec->catfile( $runtime_dir, 'listener.inbox.jsonl' ),
        pid_file     => File::Spec->catfile( $runtime_dir, 'listener.pid' ),
        log_file     => File::Spec->catfile( $runtime_dir, 'listener.log' ),
    };
}

sub listener_session_id {
    my ($self) = @_;
    my $session_id = $self->env_value('TELEGRAM_CODEX_SESSION_ID');
    $session_id = $self->env_value('CODEX_SESSION_ID') if !defined $session_id || $session_id eq q{};
    return $self->normalise_session_id($session_id);
}

sub normalise_session_id {
    my ( $self, $session_id ) = @_;
    $session_id = 'default' if !defined $session_id || $session_id eq q{};
    $session_id =~ s{[^A-Za-z0-9_.-]+}{-}g;
    $session_id =~ s{\A-+}{};
    $session_id =~ s{-+\z}{};
    return $session_id eq q{} ? 'default' : $session_id;
}

sub read_listener_offset {
    my ( $self, $path ) = @_;
    return undef if !-f $path;
    my $content = $self->read_text_file($path);
    $content =~ s/\s+\z//;
    return undef if $content eq q{};
    return 0 + $content;
}

sub write_listener_offset {
    my ( $self, $path, $offset ) = @_;
    return $self->write_text_file( $path, $offset . "\n" );
}

sub recover_listener_offset_from_inbox {
    my ( $self, $path ) = @_;
    return undef if !-f $path;
    my @lines = grep { defined $_ && $_ ne q{} } split /\n/, $self->read_text_file($path);
    for my $line ( reverse @lines ) {
        my $decoded = eval { decode_json($line) };
        next if $@ || ref($decoded) ne 'HASH';
        next if !defined $decoded->{update_id};
        return $decoded->{update_id} + 1;
    }
    return undef;
}

sub append_inbox_entry {
    my ( $self, $path, $entry ) = @_;
    make_path( dirname($path) ) if !-d dirname($path);
    open my $fh, '>>', $path or die "Unable to append $path: $!";
    print {$fh} encode_json($entry) . "\n";
    close $fh or die "Unable to close $path: $!";
    return $path;
}

sub update_needs_listener_reply {
    my ( $self, $summary ) = @_;
    return 1 if defined $summary->{text}     && $summary->{text} ne q{};
    return 1 if defined $summary->{caption}  && $summary->{caption} ne q{};
    return 1 if $summary->{photo};
    return 1 if $summary->{document};
    return 1 if $summary->{audio};
    return 1 if $summary->{video};
    return 1 if $summary->{voice};
    return 0;
}

sub resolve_token {
    my ( $self, $explicit ) = @_;
    my $token = defined $explicit && $explicit ne q{}
      ? $explicit
      : $self->env_value('TELEGRAM_BOT_TOKEN');
    die "TELEGRAM_BOT_TOKEN is required\n" if !defined $token || $token eq q{};
    return $token;
}

sub env_value {
    my ( $self, $key ) = @_;
    return $self->{env}{$key};
}

sub resolve_path {
    my ( $self, $path ) = @_;
    return undef if !defined $path;
    if ( $path eq '~' ) {
        return $self->{home};
    }
    if ( defined $self->{home} && $path =~ m{\A~/} ) {
        return File::Spec->catfile( $self->{home}, substr( $path, 2 ) );
    }
    return $path;
}

sub basename {
    my ( $self, $path ) = @_;
    $path =~ s{\\}{/}g;
    my @parts = split m{/}, $path;
    return $parts[-1];
}

sub encode_pretty_json {
    my ( $self, $data ) = @_;
    return JSON::XS->new->utf8->pretty->canonical->encode($data);
}

sub write_text_file {
    my ( $self, $path, $content ) = @_;
    make_path( dirname($path) ) if !-d dirname($path);
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} $content;
    close $fh or die "Unable to close $path: $!";
    return $path;
}

sub read_text_file {
    my ( $self, $path ) = @_;
    open my $fh, '<', $path or die "Unable to read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh or die "Unable to close $path: $!";
    return $content;
}

sub _build_ua {
    my ($self) = @_;
    my $ua = LWP::UserAgent->new(
        agent   => 'telegram-codex/0.09',
        timeout => 60,
    );
    return $ua;
}

sub _default_skill_root {
    my ($class) = @_;
    return File::Spec->rel2abs(
        File::Spec->catdir( dirname(__FILE__), File::Spec->updir, File::Spec->updir, File::Spec->updir )
    );
}

sub _merged_env {
    my ($self) = @_;
    my %env = %ENV;
    for my $skill_env ( $self->_env_candidate_files ) {
        next if !-f $skill_env;
        open my $fh, '<', $skill_env or die "Unable to read $skill_env: $!";
        while ( my $line = <$fh> ) {
            chomp $line;
            next if $line !~ /^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$/;
            $env{$1} = $2 if !exists $env{$1} || !defined $env{$1} || $env{$1} eq q{};
        }
        close $fh or die "Unable to close $skill_env: $!";
    }
    return \%env;
}

sub _env_candidate_files {
    my ($self) = @_;
    my @files;
    my %seen;
    my $dir = $self->{cwd};
    while ( defined $dir && $dir ne q{} ) {
        my $path = File::Spec->catfile( $dir, '.env' );
        if ( !$seen{$path}++ ) {
            push @files, $path;
        }
        my $parent = dirname($dir);
        last if !defined $parent || $parent eq $dir;
        $dir = $parent;
    }
    my $skill_root_env = File::Spec->catfile( $self->{skill_root}, '.env' );
    if ( !$seen{$skill_root_env}++ ) {
        push @files, $skill_root_env;
    }
    return @files;
}

1;
