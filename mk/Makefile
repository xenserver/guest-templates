USE_BRANDING := yes
IMPORT_VERSIONS := yes
include $(B_BASE)/common.mk
include $(B_BASE)/rpmbuild.mk

REPO = $(call git_loc,guest-templates)
CSET_NUMBER := $(shell $(shell $(call git_cset_number,guest-templates)); echo $$CSET_NUMBER)

.PHONY: build
build: srpm
	$(RPMBUILD) --target $(DOMAIN0_ARCH_OPTIMIZED) -bb $(RPM_SPECSDIR)/guest-templates.spec

.PHONY: srpm
srpm: $(RPM_DIRECTORIES)
	cd $(REPO) && git archive --format=tar --prefix=guest-templates-$(PLATFORM_VERSION)/ `cat .git/refs/heads/master` \
		| bzip2 > $(RPM_SOURCESDIR)/guest-templates-$(PLATFORM_VERSION).tar.bz2
	sed 's/@VERSION@/$(PLATFORM_VERSION)/; s/@RELEASE@/$(CSET_NUMBER)/' < ../guest-templates.spec > $(RPM_SPECSDIR)/guest-templates.spec
	$(RPMBUILD) --target $(DOMAIN0_ARCH_OPTIMIZED) -bs $(RPM_SPECSDIR)/guest-templates.spec

.PHONY: clean
clean:
	rm -f $(OUTPUT)
	$(MAKE) -C $(REPO) clean
