debug:
	odin build . --debug -out:sea.exe
release:
	odin build . -out:sea.exe -subsystem:windows
bundle: release
	7z a -tzip -r SeaStory.zip res/* sea.exe
clean:
	-rm *.pdb *.exe SeaStory.zip
	-rm SeaStory -rf

