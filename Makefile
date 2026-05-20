PERL ?= perl

install:
	PERL5LIB=lib $(PERL) -MTelegram::Codex::Manager -e 'Telegram::Codex::Manager->new()->auto_setup()'
