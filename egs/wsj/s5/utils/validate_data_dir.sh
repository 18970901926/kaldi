#!/bin/bash


 no_feats=false
 no_wav=false
 no_text=false

for x in `seq 3`; do
  if [ $1 == "--no-feats" ]; then
    no_feats=true
    shift;
  fi
  if [ $1 == "--no-text" ]; then
    no_text=true
    shift;
  fi
  if [ $1 == "--no-wav" ]; then
    no_wav=true
    shift;
  fi
done

if [ $# -ne 1 ]; then
  echo "Usage: $0 [---no-feats] [---no-text] [---no-wav] data-dir"
  echo "e.g.: $0 data/train"
fi

data=$1

if [ ! -d $data ]; then
  echo "$0: no such directory $data"
  exit 1;
fi

for f in spk2utt utt2spk; do
  if [ ! -f $data/$f ]; then
    echo "$0: no such file $f"
    exit 1;
  fi
  if [ ! -s $data/$f ]; then
    echo "$0: empty file $f"
    exit 1;
  fi
done

! cat $data/utt2spk | awk '{if (NF != 2) exit(1); }' && \
  echo "$0: $data/utt2spk has wrong format." && exit;

tmpdir=$(mktemp -d);
trap 'rm -rf "$tmpdir"' EXIT HUP INT PIPE TERM

export LC_ALL=C

function check_sorted {
  ! cat $1 | sort | cmp -s - $1 && \
    echo "$0: file $1 is not in sorted order" && exit 1;
  
}
function partial_diff {
  diff $1 $2 | head -n 6
  echo "..."
  diff $1 $2 | tail -n 6
  n1=`cat $1 | wc -l`
  n2=`cat $2 | wc -l`
  echo "[Lengths are $1=$n1 versus $2=$n2]"
}

check_sorted $data/utt2spk

! cat $data/utt2spk | sort -k2 | cmp -s - $data/utt2spk && \
   echo "$0: utt2spk is not in sorted order when sorted first on speaker-id " && \
   echo "(fix this by making speaker-ids prefixes of utt-ids)" && exit 1;

check_sorted $data/spk2utt

! cmp -s <(cat $data/utt2spk | awk '{print $1, $2;}') \
     <(utils/spk2utt_to_utt2spk.pl $data/spk2utt)  && \
   echo "$0: spk2utt and utt2spk do not seem to match" && exit 1;

cat $data/utt2spk | awk '{print $1;}' > $tmpdir/utts

if [ ! -f $data/text ] && ! $no_text; then
  echo "$0: no such file $data/text (if this is by design, specify ---no-text)"
  exit 1;
fi

num_utts=`cat $tmpdir/utts | wc -l`
if [ -f $data/text ]; then
  check_sorted $data/text
  text_len=`cat $data/text | wc -l`
  awk '{print $1}' < $data/text > $tmpdir/utts.txt
  if ! cmp -s $tmpdir/utts{,.txt}; then
    echo "$0: Error: in $data, utterance lists extracted from utt2spk and text"
    echo "$0: differ, partial diff is:"
    partial_diff $tmpdir/utts{,.txt}
    exit 1;
  fi
fi

if [ -f $data/segments ] && [ ! -f $data/wav.scp ]; then
  echo "$0: in directory $data, segments file exists but no wav.scp"
  exit 1;
fi


if [ ! -f $data/wav.scp ] && ! $no_wav; then
  echo "$0: no such file $data/wav.scp (if this is by design, specify ---no-wav)"
  exit 1;
fi

if [ -f $data/wav.scp ]; then
  check_sorted $data/wav.scp

  if [ -f $data/segments ]; then

    check_sorted $data/segments
    # We have a segments file -> interpret wav file as "recording-ids" not utterance-ids.
    ! cat $data/segments | \
      awk '{if (NF != 4 || !($4 > $3)) { print "Bad line in segments file", $0; exit(1); }}' && \
      echo "$0: badly formatted segments file" && exit 1;
    
    segments_len=`cat $data/segments | wc -l`
    ! cmp -s $tmpdir/utts <(awk '{print $1}' <$data/text) && \
      echo "$0: Utterance list differs between $data/text and $data/segments " && \
      echo "$0: Lengths are $segments_len vs $num_utts";

    cat $data/segments | awk '{print $2}' | sort | uniq > $tmpdir/recordings
    awk '{print $1}' $data/wav.scp > $tmpdir/recordings.wav
    if ! cmp -s $tmpdir/recordings{,.wav}; then
      echo "$0: Error: in $data, recording-ids extracted from segments and wav.scp"
      echo "$0: differ, partial diff is:"
      partial_diff $tmpdir/recordings{,.wav}
      exit 1;
    fi
    if [ -f $data/reco2file_and_channel ]; then
      # this file is needed only for ctm scoring; it's indexed by recording-id.
      check_sorted $data/reco2file_and_channel
      ! cat $data/reco2file_and_channel | \
        awk '{if (NF != 3 || ($3 != "A" && $3 != "B")) { print "Bad line ", $0; exit 1; }}' && \
        echo "$0: badly formatted reco2file_and_channel file" && exit 1;
      cat $data/reco2file_and_channel | awk '{print $1}' > $tmpdir/recordings.r2fc
      if ! cmp -s $tmpdir/recordings{,.r2fc}; then
        echo "$0: Error: in $data, recording-ids extracted from segments and reco2file_and_channel"
        echo "$0: differ, partial diff is:"
        partial_diff $tmpdir/recordings{,.r2fc}
        exit 1;
      fi
    fi
  else
    # No segments file -> assume wav.scp indexed by utterance.
    cat $data/wav.scp | awk '{print $1}' > $tmpdir/utts.wav
    if ! cmp -s $tmpdir/utts{,.wav}; then
      echo "$0: Error: in $data, utterance lists extracted from utt2spk and wav.scp"
      echo "$0: differ, partial diff is:"
      partial_diff $tmpdir/utts{,.wav}
      exit 1;
    fi

    if [ -f $data/reco2file_and_channel ]; then
      # this file is needed only for ctm scoring; it's indexed by recording-id.
      check_sorted $data/reco2file_and_channel
      ! cat $data/reco2file_and_channel | \
        awk '{if (NF != 3 || ($3 != "A" && $3 != "B")) { print "Bad line ", $0; exit 1; }}' && \
        echo "$0: badly formatted reco2file_and_channel file" && exit 1;
      cat $data/reco2file_and_channel | awk '{print $1}' > $tmpdir/utts.r2fc
      if ! cmp -s $tmpdir/utts{,.r2fc}; then
        echo "$0: Error: in $data, utterance-ids extracted from segments and reco2file_and_channel"
        echo "$0: differ, partial diff is:"
        partial_diff $tmpdir/utts{,.r2fc}
        exit 1;
      fi
    fi
  fi
fi

if [ ! -f $data/feats.scp ] && ! $no_feats; then
  echo "$0: no such file $data/feats.scp (if this is by design, specify ---no-feats)"
  exit 1;
fi

if [ -f $data/feats.scp ]; then
  check_sorted $data/feats.scp
  cat $data/feats.scp | awk '{print $1}' > $tmpdir/utts.feats
  if ! cmp -s $tmpdir/utts{,.feats}; then
    echo "$0: Error: in $data, utterance-ids extracted from utt2spk and features"
    echo "$0: differ, partial diff is:"
    partial_diff $tmpdir/utts{,.feats}
    exit 1;
  fi
fi

if [ -f $data/cmvn.scp ]; then
  check_sorted $data/cmvn.scp
  cat $data/cmvn.scp | awk '{print $1}' > $tmpdir/speakers.cmvn
  cat $data/spk2utt | awk '{print $1}' > $tmpdir/speakers
  if ! cmp -s $tmpdir/speakers{,.cmvn}; then
    echo "$0: Error: in $data, speaker lists extracted from spkutt and cmvn"
    echo "$0: differ, partial diff is:"
    partial_diff $tmpdir/speakers{,.cmvn}
    exit 1;
  fi
fi

echo "Successfully validated data-directory $data"
