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
    return {
        mode      => 'install',
        plugin    => 'telegram-codex',
        installed => \@installed,
    };
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
      : 'telegram-codex listener is live. Your message was received and queued for Codex.';

    my $paths = $self->listener_paths;
    make_path( $paths->{runtime_dir} ) if !-d $paths->{runtime_dir};
    my $offset = $self->read_listener_offset( $paths->{offset_file} );
    my $cycles = 0;
    my $processed = 0;
    my $replied = 0;

    while (1) {
        my %params = (
            limit   => 20,
            timeout => $poll_timeout,
        );
        $params{offset} = $offset if defined $offset;
        my $result = $self->telegram_get( 'getUpdates', \%params );
        my @updates = @{ $result->{result} || [] };
        for my $update (@updates) {
            my $summary = $self->summarise_update($update);
            $self->append_inbox_entry( $paths->{inbox_file}, $summary );
            $processed++;
            my $message = $update->{message} || $update->{edited_message} || {};
            my $chat_id = $message->{chat}{id};
            if ( defined $chat_id && $self->update_needs_listener_reply($summary) ) {
                $self->telegram_post(
                    'sendMessage',
                    {
                        chat_id             => $chat_id,
                        text                => $reply_text,
                        reply_to_message_id => $message->{message_id},
                    }
                );
                $replied++;
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
EOF
}

sub plugin_script_python {
    return <<'EOF';
#!/usr/bin/env python3
import json
import mimetypes
import os
import pathlib
import sys

import requests


PLUGIN_ROOT = pathlib.Path(__file__).resolve().parent.parent
ENV_FILE = PLUGIN_ROOT / ".env"
DOWNLOAD_ROOT = PLUGIN_ROOT / "downloads"
SERVER_NAME = "telegram-codex-bot"
SERVER_VERSION = "0.2.0"
PROTOCOL_VERSION = "2024-11-05"


def load_env_file(path):
    env = {}
    if not path.exists():
        return env
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip()
    return env


FILE_ENV = load_env_file(ENV_FILE)


def env_value(name):
    value = os.environ.get(name)
    if value:
        return value
    return FILE_ENV.get(name)


def bot_token():
    token = env_value("TELEGRAM_BOT_TOKEN")
    if not token:
        raise RuntimeError("Missing TELEGRAM_BOT_TOKEN in plugin .env or process environment")
    return token


def bot_api(method):
    return f"https://api.telegram.org/bot{bot_token()}/{method}"


def bot_file_url(file_path):
    return f"https://api.telegram.org/file/bot{bot_token()}/{file_path}"


def telegram_request(method, *, params=None, files=None):
    response = requests.post(bot_api(method), data=params, files=files, timeout=60)
    response.raise_for_status()
    payload = response.json()
    if not payload.get("ok"):
        raise RuntimeError(f"Telegram API error for {method}: {payload}")
    return payload


def telegram_get(method, *, params=None):
    response = requests.get(bot_api(method), params=params, timeout=60)
    response.raise_for_status()
    payload = response.json()
    if not payload.get("ok"):
        raise RuntimeError(f"Telegram API error for {method}: {payload}")
    return payload


def summarise_update(update):
    message = update.get("message") or update.get("edited_message") or {}
    chat = message.get("chat") or {}
    photos = message.get("photo") or []
    best_photo = photos[-1] if photos else None
    return {
        "update_id": update.get("update_id"),
        "message_id": message.get("message_id"),
        "date": message.get("date"),
        "chat": {
            "id": chat.get("id"),
            "type": chat.get("type"),
            "title": chat.get("title"),
            "username": chat.get("username"),
            "first_name": chat.get("first_name"),
            "last_name": chat.get("last_name"),
        },
        "from": message.get("from"),
        "text": message.get("text"),
        "caption": message.get("caption"),
        "photo": best_photo,
        "document": message.get("document"),
        "audio": message.get("audio"),
        "video": message.get("video"),
        "voice": message.get("voice"),
    }


def tool_get_me(_arguments):
    return telegram_get("getMe")["result"]


def tool_get_updates(arguments):
    params = {}
    for key in ("offset", "limit", "timeout"):
        if arguments.get(key) is not None:
            params[key] = arguments[key]
    if arguments.get("allowed_updates") is not None:
        params["allowed_updates"] = json.dumps(arguments["allowed_updates"])
    payload = telegram_get("getUpdates", params=params)
    updates = payload["result"]
    return {
        "count": len(updates),
        "updates": [summarise_update(item) for item in updates],
        "next_offset": (updates[-1]["update_id"] + 1) if updates else arguments.get("offset"),
    }


def tool_download_file(arguments):
    file_id = arguments["file_id"]
    target_dir = pathlib.Path(arguments.get("target_dir") or DOWNLOAD_ROOT)
    target_dir.mkdir(parents=True, exist_ok=True)
    file_info = telegram_get("getFile", params={"file_id": file_id})["result"]
    file_path = file_info["file_path"]
    response = requests.get(bot_file_url(file_path), timeout=120)
    response.raise_for_status()
    filename = arguments.get("filename") or pathlib.Path(file_path).name
    destination = target_dir / filename
    destination.write_bytes(response.content)
    return {
        "file_id": file_id,
        "telegram_file_path": file_path,
        "saved_to": str(destination),
        "bytes": destination.stat().st_size,
    }


def tool_send_message(arguments):
    result = telegram_request("sendMessage", params={
        "chat_id": arguments["chat_id"],
        "text": arguments["text"],
    })["result"]
    return {
        "chat_id": result["chat"]["id"],
        "message_id": result["message_id"],
        "text": result.get("text"),
    }


def tool_send_photo(arguments):
    photo_path = pathlib.Path(arguments["photo_path"]).expanduser().resolve()
    with photo_path.open("rb") as photo_fh:
        result = telegram_request(
            "sendPhoto",
            params={"chat_id": arguments["chat_id"], "caption": arguments.get("caption", "")},
            files={"photo": (photo_path.name, photo_fh, "application/octet-stream")},
        )["result"]
    return {
        "chat_id": result["chat"]["id"],
        "message_id": result["message_id"],
        "caption": result.get("caption"),
    }


def tool_send_document(arguments):
    document_path = pathlib.Path(arguments["document_path"]).expanduser().resolve()
    mime_type = mimetypes.guess_type(document_path.name)[0] or "application/octet-stream"
    with document_path.open("rb") as document_fh:
        result = telegram_request(
            "sendDocument",
            params={"chat_id": arguments["chat_id"], "caption": arguments.get("caption", "")},
            files={"document": (document_path.name, document_fh, mime_type)},
        )["result"]
    return {
        "chat_id": result["chat"]["id"],
        "message_id": result["message_id"],
        "caption": result.get("caption"),
    }


def tool_auto_reply_start(arguments):
    payload = telegram_get("getUpdates", params={"limit": arguments.get("limit", 20), "timeout": arguments.get("timeout", 0)})
    updates = payload["result"]
    reply_text = arguments.get("reply_text") or "Talbot Telegram bridge is live. Send text, photos, or files here and ask Codex to poll and reply."
    replied = []
    for update in updates:
        message = update.get("message") or update.get("edited_message") or {}
        text = (message.get("text") or "").strip()
        chat = message.get("chat") or {}
        if text != "/start" or not chat.get("id"):
            continue
        sent = telegram_request("sendMessage", params={
            "chat_id": chat["id"],
            "text": reply_text,
            "reply_to_message_id": message.get("message_id"),
        })["result"]
        replied.append({
            "update_id": update.get("update_id"),
            "chat_id": chat.get("id"),
            "message_id": sent.get("message_id"),
        })
    next_offset = (updates[-1]["update_id"] + 1) if updates else arguments.get("offset")
    if updates:
        telegram_get("getUpdates", params={"offset": next_offset})
    return {
        "checked": len(updates),
        "replied": replied,
        "next_offset": next_offset,
    }


TOOLS = [
    {
        "name": "telegram_get_me",
        "description": "Return the configured Telegram bot identity and capabilities.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "telegram_get_updates",
        "description": "Poll Telegram updates for new text, photos, and files.",
        "inputSchema": {"type": "object", "properties": {"offset": {"type": "integer"}, "limit": {"type": "integer"}, "timeout": {"type": "integer"}, "allowed_updates": {"type": "array", "items": {"type": "string"}}}, "additionalProperties": False},
    },
    {
        "name": "telegram_download_file",
        "description": "Download a Telegram file locally by file_id.",
        "inputSchema": {"type": "object", "properties": {"file_id": {"type": "string"}, "target_dir": {"type": "string"}, "filename": {"type": "string"}}, "required": ["file_id"], "additionalProperties": False},
    },
    {
        "name": "telegram_send_message",
        "description": "Send a text reply to a Telegram chat.",
        "inputSchema": {"type": "object", "properties": {"chat_id": {"type": ["integer", "string"]}, "text": {"type": "string"}}, "required": ["chat_id", "text"], "additionalProperties": False},
    },
    {
        "name": "telegram_send_photo",
        "description": "Send a local image file to a Telegram chat.",
        "inputSchema": {"type": "object", "properties": {"chat_id": {"type": ["integer", "string"]}, "photo_path": {"type": "string"}, "caption": {"type": "string"}}, "required": ["chat_id", "photo_path"], "additionalProperties": False},
    },
    {
        "name": "telegram_send_document",
        "description": "Send a local file to a Telegram chat as a document.",
        "inputSchema": {"type": "object", "properties": {"chat_id": {"type": ["integer", "string"]}, "document_path": {"type": "string"}, "caption": {"type": "string"}}, "required": ["chat_id", "document_path"], "additionalProperties": False},
    },
    {
        "name": "telegram_auto_reply_start",
        "description": "Poll recent updates and automatically reply to any /start messages.",
        "inputSchema": {"type": "object", "properties": {"limit": {"type": "integer"}, "timeout": {"type": "integer"}, "reply_text": {"type": "string"}}, "additionalProperties": False},
    },
]


def tool_by_name(name):
    if name == "telegram_get_me":
        return tool_get_me
    if name == "telegram_get_updates":
        return tool_get_updates
    if name == "telegram_download_file":
        return tool_download_file
    if name == "telegram_send_message":
        return tool_send_message
    if name == "telegram_send_photo":
        return tool_send_photo
    if name == "telegram_send_document":
        return tool_send_document
    if name == "telegram_auto_reply_start":
        return tool_auto_reply_start
    raise KeyError(name)


def encode_message(payload):
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    header = f"Content-Length: {len(body)}\r\n\r\n".encode("utf-8")
    return header + body


def read_message():
    header_bytes = b""
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        header_bytes += line
        if header_bytes.endswith(b"\r\n\r\n"):
            break
    headers = header_bytes.decode("utf-8").split("\r\n")
    content_length = None
    for header in headers:
        if header.lower().startswith("content-length:"):
            content_length = int(header.split(":", 1)[1].strip())
            break
    if content_length is None:
        raise RuntimeError("Missing Content-Length header")
    body = sys.stdin.buffer.read(content_length)
    return json.loads(body.decode("utf-8"))


def write_response(payload):
    sys.stdout.buffer.write(encode_message(payload))
    sys.stdout.buffer.flush()


def result_text(data):
    return {"content": [{"type": "text", "text": json.dumps(data, indent=2, ensure_ascii=False)}]}


def handle_request(request):
    method = request.get("method")
    request_id = request.get("id")
    params = request.get("params") or {}
    if method == "initialize":
        return {"jsonrpc": "2.0", "id": request_id, "result": {"protocolVersion": PROTOCOL_VERSION, "capabilities": {"tools": {}}, "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION}}}
    if method == "notifications/initialized":
        return None
    if method == "ping":
        return {"jsonrpc": "2.0", "id": request_id, "result": {}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": request_id, "result": {"tools": TOOLS}}
    if method == "tools/call":
        try:
            data = tool_by_name(params.get("name"))(params.get("arguments") or {})
            return {"jsonrpc": "2.0", "id": request_id, "result": result_text(data)}
        except Exception as exc:
            return {"jsonrpc": "2.0", "id": request_id, "result": {"content": [{"type": "text", "text": f"{type(exc).__name__}: {exc}"}], "isError": True}}
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": -32601, "message": f"Method not found: {method}"}}


def run_stdio_server():
    while True:
        request = read_message()
        if request is None:
            return 0
        response = handle_request(request)
        if response is not None:
            write_response(response)


def main(argv):
    if "--self-test" in argv:
        print(json.dumps(tool_get_me({}), indent=2))
        return 0
    if "--get-updates" in argv:
        print(json.dumps(tool_get_updates({"limit": 5, "timeout": 0}), indent=2, ensure_ascii=False))
        return 0
    if "--auto-reply-start" in argv:
        print(json.dumps(tool_auto_reply_start({"limit": 20, "timeout": 0}), indent=2, ensure_ascii=False))
        return 0
    return run_stdio_server()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
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
    my $runtime_root = $self->resolve_path( $self->env_value('TELEGRAM_CODEX_RUNTIME_DIR') || '~/.telegram-codex' );
    my $runtime_dir = File::Spec->catdir( $runtime_root, $self->listener_session_id );
    return {
        runtime_dir => $runtime_dir,
        offset_file => File::Spec->catfile( $runtime_dir, 'listener.offset' ),
        inbox_file  => File::Spec->catfile( $runtime_dir, 'listener.inbox.jsonl' ),
    };
}

sub listener_session_id {
    my ($self) = @_;
    my $session_id = $self->env_value('TELEGRAM_CODEX_SESSION_ID');
    $session_id = $self->env_value('CODEX_SESSION_ID') if !defined $session_id || $session_id eq q{};
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
        agent   => 'telegram-codex/0.03',
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
