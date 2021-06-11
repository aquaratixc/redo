redo-ifchange redo.d
ldc2 -release -Oz --boundscheck=off -m64 --gcc=clang --relocation-model=pic redo.d -of $3
strip -s $3
ln -s redo redo-ifchange
ln -s redo redo-ifcreate
