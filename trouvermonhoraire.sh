#!/bin/bash
OLDFILE="auto-mesTPs.org.old"
NEWFILE="auto-mesTPs.org"
DIFFTOOL="meld"

mv $NEWFILE $OLDFILE

echo "** MATH F 101" >> $NEWFILE
wget -O phys1.html 'http://164.15.72.157:8081/Reporting/Individual;Student%20Set%20Groups;id;%23SPLUS35F0FB?&template=Ann%E9e%20d%27%E9tude&weeks=21-36&days=1-6&periods=5-33&width=0&height=0'
perl analyze.pl phys1.html  mnemonic MATHF101 enseignement EXE | grep timestamp >> $NEWFILE


# echo "** MATH F 101" >> $NEWFILE
wget -O math1.html 'http://164.15.72.157:8081/Reporting/Individual;Student%20Set%20Groups;id;%23SPLUS35F0F2?&template=Ann%E9e%20d%27%E9tude&weeks=21-36&days=1-6&periods=5-33&width=0&height=0'
# perl analyze.pl math1.html  mnemonic MATHF101 enseignement EXE | grep timestamp >> $NEWFILE

echo "** MATH F 310" >> $NEWFILE
wget -O math3.html 'http://164.15.72.157:8081/Reporting/Individual;Student%20Set%20Groups;id;%23SPLUS35F0FA?&template=Ann%E9e%20d%27%E9tude&weeks=21-36&days=1-6&periods=5-33&width=0&height=0'
perl analyze.pl math3.html mnemonic MATHF310 enseignement EXE | grep timestamp >> $NEWFILE

$DIFFTOOL $OLDFILE $NEWFILE

echo "Info: You may want to do something with $NEWFILE, now"
echo "Warning: Don't forget to move $OLDFILE if you wish to kepe it, for it will be overwitten next time"
