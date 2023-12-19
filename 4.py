import os
import sys

DOUBLE_FORKS = ["0.1", "1.1", "2.2", "3.2"]

def print_status(code: str) -> None:
    """_summary_

    Args:
        code (str): _description_
    """
    level = int(code.split(".")[0])
    if level == 0:
        print(f"I am Parent[{level}] of all, my PID is {os.getpid()}")
    else:
        print(f"I am Child[{code}] with pid: {os.getpid()} and my Parent id: {os.getppid()}")

def double_fork_index_per_level(level: int) -> int:
    """_summary_

    Args:
        level (int): _description_

    Returns:
        int: _description_
    """
    match level:
        case 0:
            return 1
        case 1:
            return 1
        case 2:
            return 2
        case 3:
            return 2
        case _:
            raise ValueError("Level must be between 0 and 3")

def rel_pos_to_double_fork(code: str) -> int:
    level, index = [int(x) for x in code.split('.')]
    if code in DOUBLE_FORKS:
        return 0
    elif index < double_fork_index_per_level(level):
        return -1
    else:
        return 1

def calculate_child_code(parent_code: str, double_fork = False) -> str:
    parent_level, parent_index = [int(x) for x in parent_code.split('.')]
    position_to_double_fork = rel_pos_to_double_fork(parent_code)
    if position_to_double_fork == -1:
        child_index = parent_index
    elif position_to_double_fork == 1:
        child_index = parent_index + 1
    else:
        if not double_fork:
            child_index = parent_index
        else:
            child_index = parent_index + 1
    return f"{parent_level + 1}.{child_index}"

def main():
    """Main function to create a lineage of processes."""
    code = "0.1"
    for i in range(5):
        
        
        print_status(code)
        if i == 4:
            #print("No more child bearing")
            sys.exit(0)
        try:
            child_pid = os.fork()
        except OSError:
            sys.exit("Fork failed")


        if child_pid == 0:  # Child process
            #parent_level, parent_index = [int(x) for x in code.split('.')]
            code = calculate_child_code(code)
            #print("Firstborn restarts loop")
            continue
        
        else: # Parent process
            if code in DOUBLE_FORKS:
                try:
                    child_pid = os.fork()
                except OSError:
                    sys.exit("Fork failed")
                if child_pid == 0:
                    parent_level, parent_index = [int(x) for x in code.split('.')]
                    code = calculate_child_code(code, double_fork = True)
                    #print("Secondborn restarts loop ")
                    continue
                else:
                    os.wait()
                    os.wait()
                    sys.exit(0)
                    break
            else:
                os.wait()
                sys.exit(0)
                break
    sys.exit(0)  # Proper exit

if __name__ == "__main__":
    main()