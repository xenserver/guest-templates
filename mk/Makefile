USE_BRANDING := yes
IMPORT_VERSIONS := yes
include $(B_BASE)/common.mk
include $(B_BASE)/rpmbuild.mk

REPO = $(call git_loc,guest-templates)
RPM_BINDIR = $(RPM_RPMSDIR)/$(DOMAIN0_ARCH_OPTIMIZED)
CSET_NUMBER := $(shell $(shell $(call git_cset_number,guest-templates)); echo $$CSET_NUMBER)
VERSION := $(PLATFORM_VERSION)-$(CSET_NUMBER)

.PHONY: build
build: srpm $(MY_SOURCES)/MANIFEST
	$(RPMBUILD) --target $(DOMAIN0_ARCH_OPTIMIZED) -bb $(RPM_SPECSDIR)/guest-templates.spec
	mkdir -p $(MY_OUTPUT_DIR) $(MY_MAIN_PACKAGES)
	# Deliberately omit the debuginfo RPM (v6d-debuginfo-0...)
	cp $(RPM_BINDIR)/guest-templates-$(VERSION).*.rpm $(MY_MAIN_PACKAGES)

.PHONY: srpm
srpm:
	mkdir -p $(RPM_SRPMSDIR) $(RPM_SPECSDIR) $(RPM_SOURCESDIR) $(RPM_RPMSDIR)
	cd $(REPO) && git archive --format=tar --prefix=guest-templates-$(PLATFORM_VERSION)/ `cat .git/refs/heads/master` \
		| bzip2 > $(RPM_SOURCESDIR)/guest-templates-$(PLATFORM_VERSION).tar.bz2
	sed 's/@VERSION@/$(PLATFORM_VERSION)/; s/@RELEASE@/$(CSET_NUMBER)/' < ../guest-templates.spec > $(RPM_SPECSDIR)/guest-templates.spec
	$(RPMBUILD) --target $(DOMAIN0_ARCH_OPTIMIZED) -bs $(RPM_SPECSDIR)/guest-templates.spec

$(MY_SOURCES)/MANIFEST: $(MY_SOURCES_DIRSTAMP)
	rm -f $@
	/bin/sh ./srpms-to-manifest guest-templates $(MY_OUTPUT_DIR)/SRPMS > $@

.PHONY: clean
clean:
	rm -f $(OUTPUT)
	$(MAKE) -C $(REPO) clean
