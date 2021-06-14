import std.algorithm;
import std.digest.md;
import std.file;
import std.format;
import std.path;
import std.process;
import std.stdio;
import std.string;

enum MESSAGE_TYPE
{
	ERROR,
	INFO,
	LOG,
	WARNING
}

auto notify(string message, MESSAGE_TYPE messageType)
{
	string preMessage = message;
	final switch (messageType) with (MESSAGE_TYPE)
	{
		case ERROR:
			preMessage = format("\u001b[31m\u001b[49m\u001b[1mError:\u001b[0m\u001b[97m\u001b[49m\u001b[1m %s \u001b[0m", message);
			break;
		case INFO:
			preMessage = format("\u001b[32m\u001b[49m\u001b[1mInfo:\u001b[0m\u001b[97m\u001b[49m\u001b[1m %s \u001b[0m", message);
			break;
		case LOG:
			preMessage = format("\u001b[34m\u001b[49m\u001b[1mLog:\u001b[0m\u001b[97m\u001b[49m\u001b[1m %s \u001b[0m", message);
			break;
		case WARNING:
			preMessage = format("\u001b[33m\u001b[49m\u001b[1mWarning:\u001b[0m\u001b[97m\u001b[49m\u001b[1m %s \u001b[0m", message);
			break;
	}
	writefln(preMessage);
}

alias error = function(string message) {
	notify(message, MESSAGE_TYPE.ERROR);
};

alias info = function(string message) {
	notify(message, MESSAGE_TYPE.INFO);
};
alias log = function(string message) {
	notify(message, MESSAGE_TYPE.LOG);
};

alias warning = function(string message) {
	notify(message, MESSAGE_TYPE.WARNING);
};

alias onlyFiles = function(string directoryPath) {
	return directoryPath.dirEntries(SpanMode.shallow).filter!`a.isFile`;
};

alias md5sum = function(string filename) {
		return File(filename)
							.byChunk(4096 * 1024)
							.digest!MD5
							.toHexString
							.toLower;
};

alias getExtension = function(string filepath) {
		return filepath.extension.replace(".", "");
};

// apply a transversal function to all files in directory
auto applyToAllFiles(string directoryPath, string[] fileArguments, void delegate(string filePath, string[] fileArguments) transversalFunction)
{
	foreach (f; directoryPath.onlyFiles)
	{
		transversalFunction(f, fileArguments);
	}
}

// read one line from file and return it
auto lineFromFile(string filePath)
{
	return File(filePath).readln.strip;
}

// write one line to file
auto lineToFile(string line, string filePath)
{
	File file;
	file.open(filePath, `w`);
	scope(exit)
	{
		file.close;
	}
	file.writeln(line);
}

void main(string[] arguments)
{
	string programName = arguments[0];
	enum string metaDirectory = `.redo`;
	
	// remove dependency file
	alias removeDependencyFile = delegate(string filePath, string[] fileArguments) {
		auto content = lineFromFile(filePath);
		if (content == fileArguments[0])
		{
			remove(filePath);
		}
	};
	
	auto cleanChangeSum(string dependency, string target)
	{
		auto changeDirectory = format(metaDirectory ~ "/%s/change/", target);
		applyToAllFiles(changeDirectory, [dependency], removeDependencyFile);
	}
	
	auto cleanCreateSum(string dependency, string target)
	{
		auto createDirectory = format(metaDirectory ~ "/%s/create/", target);
		applyToAllFiles(createDirectory, [dependency], removeDependencyFile);
	}
	
	auto cleanAll(string target)
	{
		auto targetDirectory = metaDirectory ~ "/" ~ target;
		if (targetDirectory.exists)
		{
			foreach (w; targetDirectory.onlyFiles)
			{
				remove(w);
			}
		}
	}
	
	auto getChangeSum(string dependency, string target)
	{
		string changeSum;
		auto changeDirectory = format(metaDirectory ~ "/%s/change/", target);
		
		foreach (c; changeDirectory.onlyFiles)
		{
			if (lineFromFile(c) == dependency)
			{
				changeSum = baseName(c);
			}
		}
		
		return changeSum;
	}
	
	auto upToDate(string dependency, string target)
	{
		string oldSum;
		auto changeDirectory = format(metaDirectory ~ "/%s/change/", target);
		
		foreach (d; changeDirectory.onlyFiles)
		{	
			if (lineFromFile(d) == dependency)
			{
				oldSum = baseName(d);
			}
		}
		
		return (md5sum(dependency) == oldSum);
	}
	
	auto doPath(string target)
	{
		string doFilePath;
		
		if (target.getExtension != "do")
		{
			if ((target ~ ".do").exists)
			{
				doFilePath = target ~ ".do";
			}
			else
			{
				auto path = format(`%s/default.%s.do`, target.dirName, target.getExtension);
				if (path.exists)
				{
					doFilePath = path;
				}
			}
		}
		
		return doFilePath;
	}
	
	auto genChangeSum(string dependency, string target)
	{
		cleanChangeSum(dependency, target);
		auto path = format(metaDirectory ~ "/%s/change/%s", target, md5sum(dependency));
		lineToFile(dependency, path);
	}
	
	auto genCreateSum(string dependency, string target)
	{
		cleanCreateSum(dependency, target);
		auto path = format(metaDirectory ~ "/%s/create/%s", target, md5sum(dependency));
		lineToFile(dependency, path);
	}
	
	auto getShebang(string filepath)
	{
		string shebang;

		foreach (line; File(filepath).byLine)
		{
			if (startsWith(cast(string) line, "#!"))
			{
				shebang = strip(cast(string) line);
				break;
			}
		}
		
		return shebang;
	}
	
	auto doRedo(string target)
	{
		string tmp = target ~ `---redoing`;
		string doFilePath = doPath(target);
		
		auto createDirectory = format(metaDirectory ~ `/%s/create/`, target);
		auto changeDirectory = format(metaDirectory ~ `/%s/change/`, target);
		
		if (!createDirectory.exists)
		{
			mkdirRecurse(createDirectory);
		}
		
		if (!changeDirectory.exists)
		{
			mkdirRecurse(changeDirectory);
		}
		
		if (doFilePath == "")
		{
			if (!target.exists)
			{
				error(format(`No .do file found for target: %s`, target));
				return;
			}
		}
		else
		{
			bool trigger;
			
			bool isPrepared = (upToDate(doFilePath, target) || (target.exists));
			
			if (!isPrepared)
			{
				trigger = true;
			}
			
			if (!trigger)
			{
				foreach (e; createDirectory.onlyFiles)
				{
					auto dependency = lineFromFile(e);
					
					if (dependency.exists)
					{
						warning(format(`%s exists but should be created`, dependency));
						return;
					}
					else
					{
						trigger = true;
					}
				}
			}
			
			if (!trigger)
			{
				foreach (f; changeDirectory.onlyFiles)
				{
						auto dependency = lineFromFile(f);
						auto shell = executeShell(`REDO_TARGET="%s" redo-ifchange "%s"`.format(target, dependency));
						
						if (baseName(f) != getChangeSum(dependency, target))
						{
							trigger = true;
						}
				}
			}
		
			if (trigger)
			{
				info(format(`redo %s`, target));
				cleanAll(target);
				genChangeSum(doFilePath, target);
				
				string cmd = getShebang(doFilePath);
				string rcmd;
			
				if (cmd == "")
				{
					rcmd = format(
						`PATH=.:$PATH REDO_TARGET="%s" sh -e "%s" 0 "%s" "%s" > "%s"`, target, doFilePath, baseName(target), tmp, tmp
					);
				}
				else
				{
					rcmd = format(
						`PATH=.:$PATH REDO_TARGET="%s" sh -c "%s" "%s" 0 "%s" "%s" > "%s"`, target, cmd, doFilePath, baseName(target), tmp, tmp
					);
				}
				auto rc = executeShell(rcmd);
				
				if (rc.status != 0)
				{
					error(format(`Redo script exited with a non-zero exit code: %d`, rc.status));
					error(rc.output);
					remove(tmp);
				}
				else
				{
					if (tmp.getSize == 0)
					{
						remove(tmp);
					}
					else
					{
						copy(tmp, target);
					}
				}
			}
		}
	}
	
	string[] targets = arguments[1..$];

	switch (programName)
	{
		case "redo-ifchange":
			if (environment.get("REDO_TARGET", "") == "")
			{
				error(`REDO_TARGET not set`);
				return;
			}
			foreach (target; targets)
			{
				doRedo(target);
				string redoTarget = environment.get("REDO_TARGET", "");
				
				if (!upToDate(target, redoTarget))
				{
					genChangeSum(target, redoTarget);
				}
			}
			break;
		case "redo-ifcreate":
			if (environment.get("REDO_TARGET", "") == "")
			{
				error(`REDO_TARGET not set`);
				return;
			}
			
			foreach (target; targets)
			{
				string redoTarget = environment.get("REDO_TARGET", "");
				if (target.exists)
				{
					warning(format(`%s exists but should be created`, target));
				}
				doRedo(target);
				if (target.exists)
				{
					genCreateSum(target, redoTarget);
				}
			}
			break;
		default:
			foreach (target; targets)
			{
				environment["REDO_TARGET"] = target;
				doRedo(target);
			}
			break;
	}
}
