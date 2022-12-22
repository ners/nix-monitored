#include <libgen.h>
#include <stdlib.h>
#include <string>
#include <string_view>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

void execvp_array(char* args[]) {
	args[0] = basename(args[0]);
	execvp(args[0], args);
	exit(127);
}

void execvp_vector(std::vector<char*>&& args) {
	execvp_array(args.data());
}

int main(int argc, char* argv[]) {
	std::string const path(std::string(PATH) + ":" + getenv("PATH"));
	setenv("PATH", path.c_str(), 1);
	if (!isatty(fileno(stderr)) || argc < 2) {
		execvp_array(argv);
	}
	std::string_view const verb(argv[1]);
	if (verb == "run") {
		auto const childPid = fork();
		if (childPid < 0) {
			fprintf(stderr, "fork failed\n");
			exit(127);
		}
		if (childPid == 0) {
			std::vector<char*> args{
				(char*)"nom",
				(char*)"build",
				(char*)"--no-link"
			};
			for (int i = 2; i < argc && argv[i] != nullptr && std::string(argv[i]) != "--"; ++i) {
				args.push_back(argv[i]);
			}
			execvp_vector(std::move(args));
		}
		int childStatus;
		waitpid(childPid, &childStatus, 0);
		if (childStatus != 0) {
			exit(childStatus);
		}
		execvp_array(argv);
	}
	if (verb == "repl" || verb == "flake" || verb == "--help") {
		execvp_array(argv);
	}
	if (verb == "--version") {
		execvp_vector({(char*) "nom", (char*) "--version"});
	}
	int fd[2];
	constexpr auto const READ_END = 0;
	constexpr auto const WRITE_END = 1;
	if (pipe(fd) == -1) {
		fprintf(stderr, "pipe failed\n");
		exit(127);
	}
	auto const childPid = fork();
	if (childPid < 0) {
		fprintf(stderr, "fork failed\n");
		exit(127);
	}
	if (childPid == 0) {
		dup2(fd[WRITE_END], STDERR_FILENO);
		close(fd[READ_END]);
    	close(fd[WRITE_END]);
		execvp_array(argv);
	}
	dup2(fd[READ_END], STDIN_FILENO);
    close(fd[WRITE_END]);
    close(fd[READ_END]);
	execvp_vector({(char*) "nom"});
}
