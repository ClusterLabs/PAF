# export png:
# make DRAWIO_HOME=/home/ioguix/git/drawio-desktop

DRAWIO_HOME=/change/me
DRAWIO=npm start --prefix "$(DRAWIO_HOME)" -- --no-sandbox -x -f png --border=30 --height=800

ALLPNG=pcmk-archi-all.png        pcmk-archi-cib.png         pcmk-archi-crmd.png
ALLPNG+=pcmk-archi-fencing.png   pcmk-archi-pengine.png     pcmk-archi-resource.png
ALLPNG+=pcmk-archi-dc.png        pcmk-archi-transition.png  pcmk-archi-paf-overview.png
ALLPNG+=paf-ms-roles.png         paf-ms-roles-notify.png    paf-election.png
ALLPNG+=paf-standby-recover.png  paf-primary-recover.png


all: $(ALLPNG)

clean:
	rm -f $(ALLPNG)

pcmk-archi-all.png: $(CURDIR)/pcmk-archi.xml
	$(DRAWIO) --page-index=0 -o "$(CURDIR)/$@" $(CURDIR)/pcmk-archi.xml

pcmk-archi-cib.png: $(CURDIR)/pcmk-archi.xml
	$(DRAWIO) --page-index=1 -o "$(CURDIR)/$@" $(CURDIR)/pcmk-archi.xml

pcmk-archi-crmd.png: $(CURDIR)/pcmk-archi.xml
	$(DRAWIO) --page-index=2 -o "$(CURDIR)/$@" $(CURDIR)/pcmk-archi.xml

pcmk-archi-dc.png: $(CURDIR)/pcmk-archi.xml
	$(DRAWIO) --page-index=3 -o "$(CURDIR)/$@" $(CURDIR)/pcmk-archi.xml

pcmk-archi-fencing.png: $(CURDIR)/pcmk-archi.xml
	$(DRAWIO) --page-index=4 -o "$(CURDIR)/$@" $(CURDIR)/pcmk-archi.xml

pcmk-archi-pengine.png: $(CURDIR)/pcmk-archi.xml
	$(DRAWIO) --page-index=5 -o "$(CURDIR)/$@" $(CURDIR)/pcmk-archi.xml

pcmk-archi-resource.png: $(CURDIR)/pcmk-archi.xml
	$(DRAWIO) --page-index=6 -o "$(CURDIR)/$@" $(CURDIR)/pcmk-archi.xml

pcmk-archi-paf-overview.png: $(CURDIR)/pcmk-archi.xml
	$(DRAWIO) --page-index=7 -o "$(CURDIR)/$@" $(CURDIR)/pcmk-archi.xml

pcmk-archi-transition.png: $(CURDIR)/pcmk-archi.xml
	$(DRAWIO) --page-index=8 -o "$(CURDIR)/$@" $(CURDIR)/pcmk-archi.xml

paf-ms-roles.png: $(CURDIR)/paf-mecha.xml
	$(DRAWIO) --page-index=0 -o "$(CURDIR)/$@" $(CURDIR)/paf-mecha.xml

paf-ms-roles-notify.png: $(CURDIR)/paf-mecha.xml
	$(DRAWIO) --page-index=1 -o "$(CURDIR)/$@" $(CURDIR)/paf-mecha.xml

paf-standby-recover.png: $(CURDIR)/paf-mecha.xml
	$(DRAWIO) --page-index=2 -o "$(CURDIR)/$@" $(CURDIR)/paf-mecha.xml

paf-primary-recover.png: $(CURDIR)/paf-mecha.xml
	$(DRAWIO) --page-index=3 -o "$(CURDIR)/$@" $(CURDIR)/paf-mecha.xml

paf-election.png: $(CURDIR)/paf-mecha.xml
	$(DRAWIO) --page-index=4 -o "$(CURDIR)/$@" $(CURDIR)/paf-mecha.xml

# paf-mecha.xml
# pcmk-archi.xml
# pcmk-archi-cib.png
# pcmk-archi-crmd.png
# pcmk-archi-dc.png
# pcmk-archi-fencing.png
# pcmk-archi-pengine.png
# pcmk-archi.png
# pcmk-archi-resource.png
# pcmk-archi.png
# pcmk-archi.xml
# Policy-Engine-big.png
