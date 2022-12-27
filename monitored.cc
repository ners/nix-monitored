#include <array>
#include <functional>
#include <iostream>
#include <libgen.h>
#include <optional>
#include <stdlib.h>
#include <string>
#include <string_view>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

#ifndef NDEBUG
#define debug std::cerr
#else
#define debug false && std::cerr
#endif

void execvp_array(char* args[])
{
	debug << "execvp:";
	for (int i = 0; args[i] != nullptr; ++i)
	{
		debug << " " << args[i];
	}
	debug << std::endl;
	execvp(args[0], args);
	exit(EXIT_FAILURE);
}

void execvp_vector(std::vector<char*>&& args)
{
	execvp_array(args.data());
}

pid_t fork_with(std::function<void()> child, std::function<void(pid_t)> parent)
{
	auto const pid = fork();
	if (pid < 0)
	{
		std::cerr << "fork failed" << std::endl;
		exit(EXIT_FAILURE);
	}
	pid == 0 ? child() : parent(pid);
	return pid;
}

int wait_for(pid_t pid)
{
	int status;
	waitpid(pid, &status, 0);
	if (status != EXIT_SUCCESS)
	{
		exit(status);
	}
	return status;
}

std::array<int, 2> make_pipe()
{
	std::array<int, 2> fd;
	if (pipe(fd.data()) == -1)
	{
		std::cerr << "pipe failed" << std::endl;
		exit(EXIT_FAILURE);
	}
	return fd;
}

int main(int argc, char* argv[])
{
	std::string const path(std::string(PATH) + ":" + getenv("PATH"));
	setenv("PATH", path.c_str(), 1);
	if (!isatty(fileno(stderr)) || argc < 2)
	{
		execvp_array(argv);
	}
	argv[0] = basename(argv[0]);
	debug << "argv:";
	for (int i = 0; argv[i] != nullptr; ++i)
	{
		debug << " " << argv[i];
	}
	debug << std::endl;
	std::string_view const command(argv[0]);
	std::string_view const verb(argv[1]);
	if (command == "nix-build" || command == "nix-shell")
	{
		argv[0][1] = 'o';
		argv[0][2] = 'm';
		execvp_array(argv);
	}
	if (verb == "build" || verb == "shell" || verb == "develop" ||
	    verb == "--version")
	{
		argv[0] = (char*)"nom";
		execvp_array(argv);
	}
	if (verb == "run")
	{
		fork_with(
		    [&]()
		    {
			    std::vector<char*> nom_args{
			        (char*)"nom", (char*)"build", (char*)"--no-link"};
			    for (int i = 2; i < argc && argv[i] != nullptr; ++i)
			    {
				    std::string_view const arg(argv[i]);
				    if (arg == "--" || arg == "--command") break;
				    nom_args.push_back(argv[i]);
			    }
			    execvp_vector(std::move(nom_args));
		    },
		    [&](auto nom_pid)
		    {
			    wait_for(nom_pid);
			    execvp_array(argv);
		    }
		);
	}
	if (verb == "repl" || verb == "flake" || verb == "--help")
	{
		execvp_array(argv);
	}
	auto const [nix_stderr_out, nix_stderr_in] = make_pipe();
	fork_with(
	    [&]()
	    {
		    close(nix_stderr_out);
		    dup2(nix_stderr_in, STDERR_FILENO);
		    execvp_array(argv);
	    },
	    [&](auto nix_pid)
	    {
		    fork_with(
		        [&]()
		        {
			        close(nix_stderr_in);
			        dup2(nix_stderr_out, STDIN_FILENO);
			        execvp_vector({(char*)"nom"});
		        },
		        [&](auto nom_pid)
		        {
			        close(nix_stderr_in);
			        close(nix_stderr_out);
			        wait_for(nix_pid);
			        wait_for(nom_pid);
			        exit(EXIT_SUCCESS);
		        }
		    );
	    }
	);
}
