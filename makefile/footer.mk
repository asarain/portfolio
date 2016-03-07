NFSDIR:=/tftpboot/root

project_showfiles: project_print
	@echo "ARCH:  $(ARCH)"
	@echo "CFLAGS:  $(CFLAGS)"
	@echo "OBJDIR:  $(OBJDIR)"
	@echo "OBJDIRS:  $(OBJDIRS)"
	@echo "BINDIR:  $(BINDIR)"
	@echo "C FILES ---------------------"
	@echo $(SOURCES)
	@echo "OBJECT FILES ---------------------"
	@echo $(OBJS)
	@echo "HEADER FILES ---------------------"
	@echo $(HEADERS)

project_print:
	@echo "---------------- $(PROGRAM) $(CONFIG)"

project_clean:
	@echo "Removing $(notdir $(EXE))"
	$(DGLOG)rm -f $(EXE)
	@echo "Removing object files"
	$(DGLOG)rm -f $(OBJS)

clean showfiles:
	$(DGLOG)for p in $(PROJECTS) ; do $(MAKE) --no-print-directory project_$@ PROGRAM_DIR=$$p CONFIG=debug ; done
	$(DGLOG)for p in $(PROJECTS) ; do $(MAKE) --no-print-directory project_$@ PROGRAM_DIR=$$p CONFIG=release ; done
