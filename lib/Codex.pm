package Codex;
use strict;
use Command;
use Parser;
use Codex::Define;
use Codex::Proof;

Command->newvar(@$_) foreach (
	[ 'number' => '(?<! \S )(\d+)(?= \s | $)', sub { pop } ],
	[ 'type' => '(?<! \S ) (\w+) (?= \s | $)', sub { pop } ],
	[ 'text' => '(?<! \S ) (.*) (?= \s | $)', sub { pop } ],
);
my @sh = map Command->new(@$_), (
	[ 'list all', 1, 'list cwc as it would be written to disk' ],
	[ 'load $type', 1, 'load the definitions for $type (without proofs)' ],
	[ 'load $type $number', 1, 'load proof of lemma $number' ],
	[ 'test $type', 1, 'test that all lemmas have a valid proof' ],
	[ 'test $type $number', 1, 'test for valid proof of lemma $number' ],
	[ 'shell $text', 0, 'shell out' ],
	[ 'debug expr', 0, 'toggle debugging of expression parsing' ],
);

sub new {
	my $proto = shift;
	my $self = bless {
		'parent' => ref($proto) ? $proto : undef
	}, ref($proto) || $proto;
	$self;
}

sub parent { shift->{'parent'} }
sub cwc { shift->{'cwc'} }

sub error {
	my($self, $text) = @_;
	$text =~ s/($)\n?/\n/;
	warn $text;
	undef;
}

sub sh {
	my $self = shift;
	my $parser = $self->parser;
	1 while defined $parser->next;
}

sub parser {
	my $self = shift;
	$self->{'parser'} ||= new Parser($self, \@sh);
}

sub define {
	my($self, $type) = @_;
	$self = $self->parent while $self->parent;
	$self->{'types'} ||= +{};
	$self->{'types'}{$type} ||= Codex::Define::new($self, "data/$type");
}

sub proof {
	my($self, $type, $index) = @_;
	my $ego = $self->define($type) or return;
	my $lemma = $ego->lemma($index);
	unless (defined $lemma) {
		$self->error("Couldn't find lemma $index");
		return;
	}
	$lemma->{'proof'} ||= Codex::Proof::new($ego, $type, $index);
}

sub unload {
	my($self, $type, $index) = @_;
	if (defined $index) {
		my $define = $self->define($type) or return;
		my $lemma = $define->lemma($index) or return;
		delete $lemma->{'proof'};
	} else {
		$self = $self->parent while $self->parent;
		return unless $self->{'types'};
		delete $self->{'types'}{$type};
	}
}

sub load {
	my($self, $type, $index) = @_;
	$self->unload($type, $index);
	my $result = defined($index)
			? $self->proof($type, $index) : $self->define($type);
	$self->{'cwc'} = $result if defined $result;
	$result;
}

sub test {
	my($self, $type, $index) = @_;
	$self->unload($type, $index);
	my $ego = $self->define($type) or return;
	my $last = $index || @{ $ego->lemmas };
	$index ||= 1;
	while ($index <= $last) {
		my $lemma = $ego->lemma($index);
		unless ($lemma) {
			$self->error("Can't locate lemma $index for '$type'");
			return;
		}
		my $proof = $self->proof($type, $index) or return;
		unless ($lemma->text eq $proof->conclusion->text) {
			$self->error(sprintf "Expecting conclusion '%s', got '%s'",
					$lemma->text, $proof->conclusion->text);
			return;
		}
		$proof->test or return;
		++$index;
	}
}

sub listall {
	my $self = shift;
	my $cwc = $self->cwc;
	if ($cwc) {
		print $cwc->text;
	} else {
		$self->error("No current codex");
	}
}

sub shell {
	system($_[1]);
}

sub debugexpr {
	Codex::Expr->debug;
}

1;
