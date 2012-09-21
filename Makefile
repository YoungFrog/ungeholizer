OPTS = -o
RUN = perl analyze.pl
FILES = horaires/chim1-g1.org horaires/chim1-g2.org horaires/irbi1-g1.org horaires/irbi1-g2.org horaires/irbi1-g3.org horaires/irbi1-g4.org horaires/math1-eco.org horaires/math1-info.org horaires/math1-phys.org horaires/phys1-g1.org horaires/phys1-g2.org horaires/phys1-g3.org horaires/scie1-ga.org horaires/scie1-gb.org horaires/scie1-gc.org

WGETTOSTDOUT = wget -O -
URLFORANET = 'http://164.15.72.157:8080/Reporting/Individual;Student%20Set%20Groups;id;%23$(1)?&template=Ann%E9e%20d%27%E9tude&weeks=1-52&days=1-6&periods=5-33&width=0&height=0'
URLFORCOURSE = 'http://164.15.72.157:8080/Reporting/Individual;Courses;name;$(1)?&template=Cours&weeks=1-52&days=1-6&periods=5-29&width=0&height=0'

GETURL=$(WGETTOSTDOUT) $(call URLFOR$(1),$(2)) > $@ 2> /dev/null
GETCURRENTCOURSE=$(call GETURL,COURSE,$(basename $@))

.PHONY: 
mathf%.htm:
	$(GETCURRENTCOURSE)
mathd%.htm:
	$(GETCURRENTCOURSE)
chim1-g1.htm: 
	$(call GETURL,ANET,SPLUS35F0FC)
chim1-g2.htm:
irbi1-g1.htm:
irbi1-g2.htm:
irbi1-g3.htm:
irbi1-g4.htm:
math1-eco.htm:
	$(call GETURL,ANET,SPLUS35F0F2)
math1-info.htm:
	$(call GETURL,ANET,SPLUS35F0F3)
math1-phys.htm:
	$(call GETURL,ANET,SPLUS35F0F4)
phys1-g1.htm:
	$(call GETURL,ANET,SPLUS35F0FB)
phys1-g2.htm:
	$(call GETURL,ANET,SPLUS35F0FC)
phys1-g3.htm:
	$(call GETURL,ANET,SPLUS35F0FD)
scie1-ga.htm:
scie1-gb.htm:
scie1-gc.htm:
irbi2.htm:
	$(call GETURL,ANET,SPLUS35F0E2)


forceall: $(addsufix TARGETS,.htm)

horaires/%.org: %.htm
	$(RUN) $(OPTS) $< > $@
