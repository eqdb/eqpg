# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

set -e

# Only reconvert if ssconvert is installed. Installing ssconvert on Travis-CI is
# painful and I could not find a suitable alternative program.
if [ ! -z `command -v ssconvert` ];
then
  echo 'Converting data.gnumeric to CSV...'
  mkdir -p ./test/tabular/data/data
  rm -f ./test/tabular/data/data.*.csv
  ssconvert -S ./test/tabular/data.gnumeric ./test/tabular/data/data.csv
  rename -v 's/data.csv.([0-9]+)/data.$1.csv/' ./test/tabular/data/data.csv.*
fi

dart ./test/tabular/run.dart ./test/tabular/model.yaml ./test/tabular/data/data.*.csv
