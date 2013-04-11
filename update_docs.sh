#!/bin/sh

CURRDIR=`pwd`
for VERSION in master `git tag -l`; do
	TMPDIR=/tmp/argument_parser-docs-$VERSION
	DESTDIR=docs-$VERSION
	rm -Rf $TMPDIR && rm -Rf $DESTDIR && mkdir -p $TMPDIR && \
		(git archive $VERSION | tar -xC $TMPDIR) && \
		cd $TMPDIR && \
		nimrod doc2 argument_parser.nim && \
		cd "${CURRDIR}" && \
		mkdir $DESTDIR && \
		cp $TMPDIR/argument_parser.html $DESTDIR && \
		git status && \
		echo "Finished updating docs"
done
