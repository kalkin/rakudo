unit class Pod::To::Text;

method render($pod) {
    pod2text($pod)
}

my &colored;
if %*ENV<POD_TO_TEXT_ANSI> {
    &colored = try {
        use MONKEY-SEE-NO-EVAL;  # safe, not using EVAL for interpolation
        EVAL q{ use Terminal::ANSIColor; &colored }
    } // sub ($text, $color) { $text }
} else {
    &colored = sub ($text, $color) { $text }
}

sub pod2text($pod) is export {
    given $pod {
        when Pod::Heading      { heading2text($pod)             }
        when Pod::Block::Code  { code2text($pod)                }
        when Pod::Block::Named { named2text($pod)               }
        when Pod::Block::Para  { twrap( $pod.contents.map({pod2text($_)}).join("") ) }
        when Pod::Block::Table { table2text($pod)               }
        when Pod::Block::Declarator { declarator2text($pod)     }
        when Pod::Item         { item2text($pod).indent(2)      }
        when Pod::FormattingCode { formatting2text($pod)        }
        when Positional        { $pod.map({pod2text($_)}).grep( { $_ !~~ Nil }).join("\n\n")}
        when Pod::Block::Comment { '' }
        when Pod::Config       { '' }
        default                { $pod.Str                       }
    }
}

sub heading2text($pod) {
    given $pod.level {
        my $content = $pod.contents.first.contents.grep( * !~~ "").first;
        my $text;
        if $content ~~ Str {
            $text = $content;
        } else {
            $text = pod2text $content;
        }
        my $name = $text.lines[0];
        my $rest = $text.lines[1…*].join: "\n";
        when 1  {
            my $result = colored($name.uc, 'bold') ~ "\n";
            $result ~= "\n$rest" if $rest.defined;
            $result.trim;
        }
        when 2  {
            my $result = '  ' ~ colored($name, 'bold') ~ "\n";
            $result ~= "\n$rest" if $rest.defined;
            $result.trim-trailing;
        }
        default { '    ' ~ pod2text($pod.contents)  }
    }
}

sub code2text($pod) {
    my $text = "    " ~ $pod.contents>>.&pod2text.subst(/\n/, "\n    ", :g);
    join "\n", $text.lines.map: { colored($_, "green")};
}

sub item2text($pod) {
    '* ' ~ pod2text($pod.contents).chomp.chomp
}

sub named2text($pod) {
    given $pod.name {
        when 'pod'  { pod2text($pod.contents)     }
        when 'para' { para2text($pod.contents[0]) }
        when 'defn' { pod2text($pod.contents[0]) ~ "\n"
                    ~ pod2text($pod.contents[1..*-1]) }
        when 'config' { }
        when 'nested' { }
        when /<:Lu>+/ { colored($pod.name, 'bold') ~ "\n\t" ~ pod2text($pod.contents) }
        default     { $pod.name ~ "\n" ~ pod2text($pod.contents) }
    }
}

sub para2text($pod) {
    twine2text($pod.contents)
}

sub table2text($pod) {
    my @rows = $pod.contents;
    @rows.unshift($pod.headers.item) if $pod.headers;
    my @maxes;
    my $cols = [max] @rows.map({ .elems });
    for 0..^$cols -> $i {
        @maxes.push([max] @rows.map({ $i < $_ ?? $_[$i].chars !! 0 }));
    }
    my $ret;
    if $pod.config<caption> {
        $ret = $pod.config<caption> ~ "\n"
    }
    for @rows -> $row {
        for 0..($row.elems - 1) -> $i {
            $ret ~= $row[$i].fmt("%-{@maxes[$i]}s") ~ "  ";
        }
        $ret ~= "\n";
    }
    $ret
}

sub declarator2text($pod) {
    next unless $pod.WHEREFORE.WHY;
    my $what = do given $pod.WHEREFORE {
        when Method {
            my @params=$_.signature.params[1..*];
              @params.pop if @params.tail.name eq '%_';
            'method ' ~ $_.name ~ signature2text(@params)
        }
        when Sub {
            'sub ' ~ $_.name ~ signature2text($_.signature.params)
        }
        when .HOW ~~ Metamodel::EnumHOW {
            "enum $_.perl() { signature2text $_.enums.pairs } \n"
        }
        when Parameter { next }
        when .HOW ~~ Metamodel::ClassHOW {
            'class ' ~ $_.perl
        }
        when .HOW ~~ Metamodel::ModuleHOW {
            'module ' ~ $_.perl
        }
        when .HOW ~~ Metamodel::PackageHOW {
            'package ' ~ $_.perl
        }
        default {
            ''
        }
    }
    "$what\n{$pod.WHEREFORE.WHY.contents}"
}

sub signature2text($params) {
      $params.elems ??
      "(\n\t" ~ $params.map(&param2text).join("\n\t") ~ "\n)" 
      !! "()";
}
sub param2text($p) {
    $p.perl ~ ',' ~ ( $p.WHY ?? ' # ' ~ $p.WHY !! ' ')
}

my %formats =
  C => "green",
  B => "red",
  L => "blue",
  X => "blue",
  D => "cyan",
  I => "bold",
  R => "inverse",
  T => "on_blue",
  K => "magenta",
;

sub formatting2text($pod) {
    my $text = $pod.contents>>.&pod2text.join;
    given $pod.type {
        when <L> {
            if $pod.meta.first {
                my $meta = $pod.meta.first;
                if $meta.starts-with: "/language/" {
                    $meta = "doc:" ~ $meta.comb[10..*].join.split('#').first;
                } elsif !$meta.contains(":") {
                    $meta = "doc:" ~ $meta;
                }
                $text ~= " <" ~ $meta ~ ">" ;
            }  else {
                $text ~= " <doc:" ~ $text ~ ">" ;
            }
            colored($text, %formats{$pod.type});
        }
        when %formats {
            colored($text, %formats{$pod.type})
        }
        when <N> {
            " ($text)"
        }
        when <E>|<P> {
            "$pod.type()\<$text\>";
        }
        default {
            $text;
        }
    }
}

sub twine2text($twine) {
    return '' unless $twine.elems;
    my $r = $twine[0];
    for $twine[1..*] -> $f, $s {
        $r ~= $f.?contents ?? twine2text($f.contents) !! $f.Str;
        $r ~= $s;
    }
    $r;
}

sub twrap($text is copy, :$wrap=75 ) {
    $text ~~ s:g/(. ** {$wrap} <[\s]>*)\s+/$0\n/;
    $text
}

# vim: ft=perl6
