# a phony target to add all git changes and commit them with a message then push them to the remote repo
# Usage: make commit message="your message here"
.PHONY: commit
commit:
	git add .
	git commit -m "$(message)"
	git push origin master
