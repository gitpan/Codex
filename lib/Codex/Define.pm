package Codex::Define;
use strict;
use Errors;
use vars qw(@ISA);
@ISA = qw(Errors);

use Command;
use Parser;
use Codex;
use Codex::Line;
use Codex::Operator;

Command->newvar(@$_) foreach (
	[ 'text' => '(.*)', sub { pop } ],
	[ 'hash' => '(\#)', sub { pop } ],
	[ 'name' => '\b(\w+)\b', sub { pop } ],
	[ 'type' => '(?<! \S ) (\w+) (?= \s | $)', sub { pop } ],
	[ 'number' => '(?<! \S ) (\d+) (?= \s | $)', sub { pop } ],
	[ 'varlist' => '\b ( (?: \w+ \s* , \s* )* \w+? ) \b',
		sub { [ split /\s*,\s*/, $_[1] ] } ],
);
my @parse = map Command->new($_->[0], 0, $_->[1]), (
	[ 'rl $hash$text', 'comment' ],
	[ 'rl use $type', 'load another definition library' ],
	[ 'rl axiom $text', 'load axiom' ],
	[ 'rl lemma $number $text', 'load lemma' ],
	[ 'rl operator $name($varlist) $text', 'load operator' ],
	[ 'rl function $name($varlist)', 'load function' ],
	[ 'rl builtin operator $name', 'load builtin operator' ],
);

sub new {
	my($proto, $file) = @_;
	my $self = bless {
		'parent' => $proto,
		'file' => $file,
	}, __PACKAGE__;
	$self->load;
}

sub lines { shift->{'lines'} ||= [] }
sub axioms { shift->{'axioms'} ||= [] }
sub lemmas { shift->{'lemmas'} ||= [] }
sub lemma { shift->lookup(+shift) }
sub operators { shift->{'operators'} ||= [] }
sub functions { shift->{'functions'} ||= [] }
sub parent { shift->{'parent'} }
sub define { shift->parent->define(@_) }
sub parser { shift->{'parser'} }
sub lookup {
	my($self, $name, $value) = @_;
	if (defined $value) {
		($self->{'lookup'} ||= +{})->{$name} = $value;
	} else {
		($self->{'lookup'} ||= +{})->{$name};
	}
}

sub index {
	my($self, $find) = @_;
	[ grep {
		my $line = $self->lines->[$_];
		ref($line) && ($line == $find)
	} 0 .. $#{ $self->lines } ]->[0];
}

sub text {
	my $self = shift;
	my $lines = [];
	push @$lines, map { $_->builtin
		? sprintf "builtin operator %s", $_->name
		: sprintf "operator %s(%s) %s",
				$_->name, join(', ', @{ $_->vars }), $_->pattern
	} @{ $self->operators };
	my($lasttype, $type) = ('lemma');
	foreach (@{ $self->lines }) {
		if (ref $_) {
			$type = $_->type;
			push @$lines, '' if $type eq 'axiom' && $lasttype eq 'lemma';
			push @$lines, sprintf "%s %s", $type, $_->expr->text;
		} else {
			$type = 'comment';
			push @$lines, '' if $lasttype ne 'comment';
			push @$lines, "#$_";
		}
		$lasttype = $type;
	}
	join '', map "$_\n", @$lines;
}

sub load {
	my $self = shift;
	my $p = $self->{'parser'} 
			= Parser->newfile($self, \@parse, $self->{'file'}, 'rl ');
	$self->error("Can't get parser for '$self->{'file'}'\n") unless $p;
	my $result = 1;
	$result = $p->next while $result && !@{ $self->errors };
	$result = 0, $self->showerrors if @{ $self->errors };
	return if defined $result;
	$self;
}

sub rl {
	my($self, $hash, $comment) = @_;
	push @{ $self->lines }, $comment;
}

sub rlaxiom {
	my($self, $line) = @_;
	my $o = Codex::Line->new($self, $line);
	if ($o) {
		$o->type('axiom');
		$o->derived(sprintf "%s:%s", $self->{'file'}, $.);
		push @{ $self->lines }, $o;
		push @{ $self->axioms }, $o;
	} else {
		$self->error("Couldn't parse axiom '$line'");
		$self->parser->quit;
	}
}

sub rllemma {
	my($self, $name, $line) = @_;
	my $o = Codex::Line->new($self, $line);
	if ($o) {
		$o->type('lemma');
		$o->name($name);
		$o->derived(sprintf "%s:%s", $self->{'file'}, $.);
		push @{ $self->lines }, $o;
		push @{ $self->lemmas }, $o;
		$self->lookup($name, $o);
	} else {
		$self->error("Couldn't parse lemma $name: '$line'");
		$self->parser->quit;
	}
}

sub rlfunction {
	my($self, $name, $vars) = @_;
	my $pattern = sprintf "%s(%s)", $name, join ', ', @$vars;
	my $o = Codex::Operator->new($name, $vars, $pattern);
	if ($o) {
		push @{ $self->functions }, $o;
		$o->prec(99999);
	} else {
		$self->error("Couldn't parse function definition");
		$self->parser->quit;
	}
}

sub rloperator {
	my($self, $name, $vars, $pattern) = @_;
	my $o = Codex::Operator->new($name, $vars, $pattern);
	if ($o) {
		push @{ $self->operators }, $o;
		$o->prec(scalar @{ $self->operators });
	} else {
		$self->error("Couldn't parse operator definition");
		$self->parser->quit;
	}
}

sub rlbuiltinoperator {
	my($self, $name) = @_;
	my $o = Codex::Operator->builtin($name);
	if ($o) {
		push @{ $self->operators }, $o;
	} else {
		$self->error("Not a builtin operator '$name'");
		$self->parser->quit;
	}
}

1;
