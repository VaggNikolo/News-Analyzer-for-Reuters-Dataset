import os
import sys
import time

# Tuple of messages
MESSAGES = (
    "I love PLH211          ",
    "The professor is boring",
    "but the curriculum is  ",
    "interesting & useful   "
)

# Creating anonymous pipe
source_to_transformer_fd = os.pipe()

# Creating named pipe (FIFO)
fifo_path = "/tmp/my_fifo"
try:
    os.mkfifo(fifo_path)
except FileExistsError:
    pass  # If FIFO already exists, we can use it

# Function to handle source process
def source_process(messages, write_end):
    for msg in messages:
        os.write(write_end, msg.encode())
        time.sleep(1)  # Simulate the time it takes to process the message
    os.close(write_end)  # Close the write end of the pipe when done

# Function to handle transformer process
def transformer_process(read_end, fifo_path):
    with open(fifo_path, 'w') as fifo:
        while True:
            try:
                message = os.read(read_end, 23).decode()
                if not message:  # If read returns an empty string, the pipe is closed
                    break
                tokens = message.strip().split()
                for token in tokens:
                    fifo.write(token + '\n')
                    fifo.flush()  # Make sure to flush after each write
            except OSError:
                break
    os.close(read_end)  # Close the read end of the pipe when done

# Function to handle output process
def output_process(fifo_path):
    try:
        with open(fifo_path, 'r') as fifo:
            for line in fifo:
                print(line.strip())
    except FileNotFoundError:
        print("Named pipe does not exist")
    except OSError as e:
        print(f"An error occurred: {e}")

# Main execution starts here
if __name__ == '__main__':
    # Start the source process
    pid = os.fork()
    if pid == 0:
        source_process(MESSAGES, source_to_transformer_fd[1])
        sys.exit()

    # Start the transformer process
    pid = os.fork()
    if pid == 0:
        transformer_process(source_to_transformer_fd[0], fifo_path)
        sys.exit()

    # Start the output process in the parent process
    output_process(fifo_path)

    # Wait for children to prevent zombies
    os.waitpid(-1, 0)
    os.waitpid(-1, 0)

    # Cleanup the FIFO
    os.remove(fifo_path)