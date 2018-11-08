#!/usr/bin/env perl6
use v6;

use Digest::MD5;
use Terminal::ANSIColor;
use Terminal::Spinners;


constant $ERROR_COLOUR    = 'red';
constant $MD5_COLOUR      = 'cyan';
constant $MATCH_COLOUR    = 'green';
constant $NO_MATCH_COLOUR = 'red';
constant $WARNING_COLOUR  = 'yellow';

grammar MD5SUM {
	token TOP        { <md5> <spacer> <filehandle> }
	token md5        { <xdigit> ** 32 }
	token spacer     { \s+ }
	token filehandle { .* }
}

class MD5Plan {
	has Str $.filehandle is required;
	has Str $.correct-md5 is rw;
	has Str $.computed-md5 is rw;

	method new (Str $filehandle where { $filehandle.IO.f }, Str $correct-md5?) {
		return $correct-md5 ?? self.bless(:$filehandle, :$correct-md5) !! self.bless(:$filehandle);
	}
}

sub calc-md5-sum (MD5Plan $plan) {
	my $md5 = Digest::MD5.new;

	print "Calculating MD5 sum for { $plan.filehandle }       "; # We need some space for the spinner to take up.
	                                                             # I like 'bounce', so I need 6 spaces for the spinner
																 # + an extra one to separate it from the filehandle.

	my Buf $buffer = $plan.filehandle.IO.slurp(:close, :bin);

	my $decoded = $buffer.decode('iso-8859-1');

	my $spinner = Spinner.new(type => 'bounce');

	my $promise = Promise.start({
		$md5.md5_hex($decoded)
	});

	until $promise.status {
		$spinner.next;
	}

	say ''; # Add a new line after the spinner.

	$plan.computed-md5 = $promise.result;
}

# Calculate the MD5 sums for the files and print them.
sub display-file-sums (Str @files) {
	my @plans = map { MD5Plan.new($_) }, @files;

	for @plans -> $plan {
		calc-md5-sum($plan);
	}

	print-plan-sums(@plans);
}

# Print MD5 sums in the md5sum format.
# If we are comparing to pre-existing sums, change the colouration to green or red
# based on whether the sums match or not.
sub print-plan-sums (@plans) {
	PRINTING: for @plans -> $plan {
		next PRINTING if !$plan.computed-md5;

		my $sumcolour = $MD5_COLOUR;

		if ($plan.correct-md5) {
			$sumcolour = $plan.correct-md5 eq $plan.computed-md5 ?? $MATCH_COLOUR !! $NO_MATCH_COLOUR;
		}

		say "{ colored($plan.computed-md5, $sumcolour) }  { $plan.filehandle }";
	}
}

# Expand directories into files.
sub expand-paths (Str @paths) {
	my @result;

	for @paths -> $path {
		given $path.IO {
			when .f { @result.push($path); }
			when .d { my Str @sub = $path.IO.dir.map({ .Str }); @result.push(|expand-paths(@sub)); }
			default { say $*ERR: colored("'$path' is not a valid path.", $ERROR_COLOUR) }
		}
	}

	return @result;
}

# Create plans for the files to scan, calculate the MD5 sums,
# and save them to the defined file.
sub create-file-sums (Str $md5sum-filehandle, Str @to-scan) {
	my MD5Plan @plans = map { MD5Plan.new($_) }, @to-scan;

	for @plans -> $plan {
		calc-md5-sum($plan);
	}

	save-md5sum-file($md5sum-filehandle, @plans);
}

# Load a file containing MD5 sums.
# We expect the format to be that of the md5sum utility:
# '<MD5>  <filehandle>' with a double space between the sum and the filehandle.
sub load-md5sum-file (Str $filehandle where { $filehandle.IO.f }) {
	my MD5Plan @plans;

	PARSE: for $filehandle.IO.lines(:close) -> $line {
		next PARSE if !$line; # We don't get worked up over blank lines.

		my $match = MD5SUM.parse($line);

		if (!$match) {
			say $*ERR: colored("Couldn't parse $line", $ERROR_COLOUR);
			next PARSE;
		}

		if (!$match<filehandle>.IO.f) {
			say $*ERR: colored("{ $match<filehandle> } isn't an existing file.", $ERROR_COLOUR);
			next PARSE;
		}

		if ($match<spacer>.chars == 2) {
			@plans.push(MD5Plan.new($match<filehandle>.Str, $match<md5>.Str));
		}
		else {
			say $*ERR: colored("'$line' does not match the output of md5sum: wrong number of spaces.", $WARNING_COLOUR);
			@plans.push(MD5Plan.new($match<filehandle>.Str, $match<md5>.Str));
		}
	}

	 return @plans;
}

# Save the MD5 sums to a file.
# We use the same format as the md5sum utility:
# '<MD5>  <filehandle>'.
sub save-md5sum-file (Str $filehandle, @plans) {
	my $io = $filehandle.IO.open: :w;

	WRITE: for @plans -> $plan {
		next WRITE unless $plan.computed-md5 && $plan.filehandle;

		$io.say("{ $plan.computed-md5 }  { $plan.filehandle }");
	}

	$io.close;
}

# Verify the MD5 sums from a file.
# If filehandles are passed, only verify those files.
sub verify-md5-sums (Str $md5sum-file, Str @filehandles?) {
	my @plans = load-md5sum-file($md5sum-file);

	if (@filehandles) {
		my @result;

		PRUNE: for @plans -> $plan {
			@result.push($plan) if $plan.filehandle ∈ @filehandles;
		}

		@plans = @result;
	}

	for @plans -> $plan {
		calc-md5-sum($plan);
	}

	print-plan-sums(@plans);
}

multi MAIN (Str :$create where { so $create }, *@files where { so @files }) {
	my Str @filehandles = @files;
	@filehandles = expand-paths(@filehandles);

	create-file-sums($create, @filehandles);
}

multi MAIN (Str :$update where { so $update }, *@files) {
	my Str @filehandles = @files;
	@filehandles = expand-paths(@filehandles);

	if (so @files) {
		#update-md5-sums($update, @filehandles);
	}
	else {
		#update-md5-sums($update);
	}
}

multi MAIN (Str :$verify where { so $verify }, *@files) {
	my Str @filehandles = @files;
	@filehandles = expand-paths(@filehandles);

	if (so @files) {
		verify-md5-sums($verify, @filehandles);
	}
	else {
		verify-md5-sums($verify);
	}
}

multi MAIN (*@files where { so @files }) {
	my Str @filehandles = @files;
	@filehandles = expand-paths(@filehandles);

	display-file-sums(@filehandles);
}
