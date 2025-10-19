"""
Structured logging utility for ContribConnect Lambda functions
Provides consistent JSON logging format for CloudWatch Logs Insights
"""

import json
import logging
import time
from datetime import datetime
from typing import Any, Dict, Optional
from functools import wraps

# Configure root logger
logging.basicConfig(
    level=logging.INFO,
    format='%(message)s'
)

logger = logging.getLogger()


class StructuredLogger:
    """Structured logger for CloudWatch with JSON output"""
    
    def __init__(self, component: str, request_id: str = ""):
        self.component = component
        self.request_id = request_id
    
    def _log(self, level: str, message: str, **kwargs):
        """Internal method to create structured log entry"""
        log_entry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "request_id": self.request_id,
            "level": level,
            "component": self.component,
            "message": message
        }
        
        # Add any additional fields
        log_entry.update(kwargs)
        
        # Print as JSON for CloudWatch
        print(json.dumps(log_entry))
    
    def info(self, message: str, **kwargs):
        """Log info level message"""
        self._log("INFO", message, **kwargs)
    
    def error(self, message: str, **kwargs):
        """Log error level message"""
        self._log("ERROR", message, **kwargs)
    
    def warning(self, message: str, **kwargs):
        """Log warning level message"""
        self._log("WARNING", message, **kwargs)
    
    def debug(self, message: str, **kwargs):
        """Log debug level message"""
        self._log("DEBUG", message, **kwargs)
    
    def tool_invocation(self, tool_name: str, action: str, duration_ms: float, 
                       status: str, **kwargs):
        """Log tool invocation with standard fields"""
        self._log(
            "INFO",
            f"Tool invocation: {tool_name}.{action}",
            tool_name=tool_name,
            action=action,
            duration_ms=round(duration_ms, 2),
            status=status,
            **kwargs
        )
    
    def guardrail_activation(self, guardrail_type: str, action: str, **kwargs):
        """Log guardrail activation"""
        self._log(
            "WARNING",
            f"Guardrail activated: {guardrail_type}",
            action=f"guardrail_{action}",
            guardrail_type=guardrail_type,
            **kwargs
        )
    
    def github_rate_limit(self, remaining: int, limit: int, reset_at: str):
        """Log GitHub API rate limit status"""
        self._log(
            "INFO",
            f"GitHub rate limit: {remaining}/{limit}",
            action="github_rate_limit",
            githubRateLimitRemaining=remaining,
            githubRateLimitTotal=limit,
            githubRateLimitResetAt=reset_at
        )
    
    def ingestion_complete(self, repo: str, records_processed: int, 
                          duration_ms: float, status: str, **kwargs):
        """Log ingestion completion"""
        self._log(
            "INFO",
            f"Ingestion complete: {repo}",
            action="ingestion_complete",
            repo=repo,
            recordsProcessed=records_processed,
            duration_ms=round(duration_ms, 2),
            status=status,
            **kwargs
        )


def log_execution(component: str):
    """Decorator to log Lambda function execution with timing"""
    def decorator(func):
        @wraps(func)
        def wrapper(event, context):
            request_id = context.request_id if hasattr(context, 'request_id') else ""
            log = StructuredLogger(component, request_id)
            
            start_time = time.time()
            
            log.info(
                f"Lambda invocation started",
                action="lambda_start",
                function_name=context.function_name if hasattr(context, 'function_name') else "",
                memory_limit_mb=context.memory_limit_in_mb if hasattr(context, 'memory_limit_in_mb') else 0
            )
            
            try:
                result = func(event, context)
                duration_ms = (time.time() - start_time) * 1000
                
                log.info(
                    f"Lambda invocation completed",
                    action="lambda_complete",
                    duration_ms=round(duration_ms, 2),
                    status="success"
                )
                
                return result
                
            except Exception as e:
                duration_ms = (time.time() - start_time) * 1000
                
                log.error(
                    f"Lambda invocation failed: {str(e)}",
                    action="lambda_error",
                    duration_ms=round(duration_ms, 2),
                    status="error",
                    error_type=type(e).__name__,
                    error_message=str(e)
                )
                
                raise
        
        return wrapper
    return decorator


def log_tool_call(log: StructuredLogger, tool_name: str, action: str):
    """Decorator to log tool call execution with timing"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            start_time = time.time()
            
            try:
                result = func(*args, **kwargs)
                duration_ms = (time.time() - start_time) * 1000
                
                log.tool_invocation(
                    tool_name=tool_name,
                    action=action,
                    duration_ms=duration_ms,
                    status="success"
                )
                
                return result
                
            except Exception as e:
                duration_ms = (time.time() - start_time) * 1000
                
                log.tool_invocation(
                    tool_name=tool_name,
                    action=action,
                    duration_ms=duration_ms,
                    status="error",
                    error_type=type(e).__name__,
                    error_message=str(e)
                )
                
                raise
        
        return wrapper
    return decorator


# Example usage:
"""
from logger import StructuredLogger, log_execution, log_tool_call

@log_execution("github-tool")
def lambda_handler(event, context):
    log = StructuredLogger("github-tool", context.request_id)
    
    # Simple log
    log.info("Processing GitHub API request", repo="owner/repo")
    
    # Tool invocation log
    log.tool_invocation(
        tool_name="github",
        action="create_pr",
        duration_ms=234.5,
        status="success",
        pr_number=123
    )
    
    # GitHub rate limit log
    log.github_rate_limit(remaining=4500, limit=5000, reset_at="2025-10-19T12:00:00Z")
    
    return {"statusCode": 200}
"""
