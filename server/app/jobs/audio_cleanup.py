"""
Audio Cleanup Job
Deletes unreferenced audio files from S3 after grace period
"""

import logging
from datetime import datetime, timedelta
from db.connection import get_database
from storage.s3_service import get_s3_service

logger = logging.getLogger(__name__)


async def cleanup_unreferenced_audio(
    grace_period_days: int = 30,
    dry_run: bool = False
):
    """
    Delete audio files with reference_count = 0 that are older than grace period
    
    Args:
        grace_period_days: Days to wait before deleting unreferenced audio
        dry_run: If True, only log what would be deleted (don't actually delete)
    
    Returns:
        dict: Statistics about cleanup operation
    """
    try:
        db = get_database()
        s3_service = get_s3_service()
        
        # Calculate cutoff date
        cutoff_date = datetime.utcnow() - timedelta(days=grace_period_days)
        cutoff_iso = cutoff_date.isoformat() + "Z"
        
        # Find candidates for deletion
        candidates = list(db.audio_files.find({
            "reference_count": 0,
            "created_at": {"$lt": cutoff_iso}
        }))
        
        logger.info(f"🔍 Found {len(candidates)} unreferenced audio files older than {grace_period_days} days")
        
        if dry_run:
            logger.info("🧪 DRY RUN - No files will be deleted")
            for audio in candidates:
                logger.info(f"   Would delete: {audio['url']} (created: {audio['created_at']})")
            return {
                "dry_run": True,
                "candidates": len(candidates),
                "deleted": 0,
                "failed": 0,
                "saved_bytes": 0
            }
        
        # Delete files
        deleted_count = 0
        failed_count = 0
        saved_bytes = 0
        
        for audio in candidates:
            try:
                # Delete from S3
                s3_deleted = s3_service.delete_file(audio["s3_key"])
                
                if s3_deleted:
                    # Delete from database
                    db.audio_files.delete_one({"id": audio["id"]})
                    
                    deleted_count += 1
                    saved_bytes += audio.get("size_bytes", 0)
                    
                    logger.info(f"✅ Deleted: {audio['url']}")
                else:
                    # S3 delete failed - mark for retry
                    db.audio_files.update_one(
                        {"id": audio["id"]},
                        {"$set": {"pending_deletion": True}}
                    )
                    failed_count += 1
                    logger.warning(f"⚠️  S3 delete failed (marked for retry): {audio['url']}")
                    
            except Exception as e:
                failed_count += 1
                logger.error(f"❌ Error deleting {audio['url']}: {e}")
        
        # Log summary
        saved_mb = saved_bytes / (1024 * 1024)
        logger.info(f"🎉 Cleanup complete:")
        logger.info(f"   Deleted: {deleted_count} files")
        logger.info(f"   Failed: {failed_count} files")
        logger.info(f"   Storage saved: {saved_mb:.2f} MB")
        
        return {
            "dry_run": False,
            "candidates": len(candidates),
            "deleted": deleted_count,
            "failed": failed_count,
            "saved_bytes": saved_bytes
        }
        
    except Exception as e:
        logger.error(f"❌ Audio cleanup job failed: {e}")
        raise


async def retry_pending_deletions():
    """
    Retry deleting audio files that failed previous deletion attempts
    
    Returns:
        dict: Statistics about retry operation
    """
    try:
        db = get_database()
        s3_service = get_s3_service()
        
        # Find files marked for deletion
        pending = list(db.audio_files.find({"pending_deletion": True}))
        
        logger.info(f"🔄 Retrying {len(pending)} pending deletions")
        
        deleted_count = 0
        still_failed = 0
        
        for audio in pending:
            # Safety check: only delete if still unreferenced
            if audio.get("reference_count", 0) > 0:
                # Reference count increased - unmark for deletion
                db.audio_files.update_one(
                    {"id": audio["id"]},
                    {"$unset": {"pending_deletion": ""}}
                )
                logger.info(f"↩️  Unmarked (now referenced): {audio['url']}")
                continue
            
            try:
                # Retry S3 deletion
                s3_deleted = s3_service.delete_file(audio["s3_key"])
                
                if s3_deleted:
                    # Success - delete from database
                    db.audio_files.delete_one({"id": audio["id"]})
                    deleted_count += 1
                    logger.info(f"✅ Retry successful: {audio['url']}")
                else:
                    still_failed += 1
                    logger.warning(f"⚠️  Retry failed again: {audio['url']}")
                    
            except Exception as e:
                still_failed += 1
                logger.error(f"❌ Retry error for {audio['url']}: {e}")
        
        logger.info(f"🔄 Retry complete: {deleted_count} deleted, {still_failed} still pending")
        
        return {
            "pending": len(pending),
            "deleted": deleted_count,
            "still_failed": still_failed
        }
        
    except Exception as e:
        logger.error(f"❌ Retry pending deletions failed: {e}")
        raise


async def verify_reference_counts():
    """
    Verify that reference counts match actual usage in messages and playlists
    Fix any drift detected
    
    Returns:
        dict: Statistics about verification operation
    """
    try:
        db = get_database()
        
        logger.info("🔍 Verifying audio reference counts...")
        
        fixed_count = 0
        verified_count = 0
        errors = []
        
        for audio in db.audio_files.find({}):
            audio_id = audio["id"]
            stored_count = audio.get("reference_count", 0)
            
            try:
                # Count actual references in messages
                message_refs = db.messages.count_documents({
                    "renders.audio_file_id": audio_id
                })
                
                # Count actual references in playlists
                playlist_refs = db.users.count_documents({
                    "playlist.audio_file_id": audio_id
                })
                
                actual_count = message_refs + playlist_refs
                
                if actual_count != stored_count:
                    # Fix drift
                    db.audio_files.update_one(
                        {"id": audio_id},
                        {"$set": {"reference_count": actual_count}}
                    )
                    
                    fixed_count += 1
                    logger.warning(
                        f"⚠️  Fixed reference count drift: {audio['url']}\n"
                        f"   Stored: {stored_count}, Actual: {actual_count} "
                        f"(messages: {message_refs}, playlists: {playlist_refs})"
                    )
                else:
                    verified_count += 1
                    
            except Exception as e:
                errors.append({"audio_id": audio_id, "error": str(e)})
                logger.error(f"❌ Error verifying {audio_id}: {e}")
        
        logger.info(f"✅ Verification complete:")
        logger.info(f"   Verified: {verified_count}")
        logger.info(f"   Fixed: {fixed_count}")
        logger.info(f"   Errors: {len(errors)}")
        
        return {
            "verified": verified_count,
            "fixed": fixed_count,
            "errors": errors
        }
        
    except Exception as e:
        logger.error(f"❌ Reference count verification failed: {e}")
        raise


async def find_orphaned_s3_files():
    """
    Find S3 files that exist but have no audio_files record
    (Usually caused by failed POST /audio calls)
    
    Note: This requires listing all S3 files, which can be slow
    
    Returns:
        list: URLs of orphaned S3 files
    """
    try:
        db = get_database()
        s3_service = get_s3_service()
        
        logger.info("🔍 Scanning for orphaned S3 files...")
        
        # Get all S3 files (this can be slow for large buckets)
        s3_files = s3_service.list_files(prefix="prod/renders/")
        
        # Get all tracked audio file URLs
        tracked_urls = set()
        for audio in db.audio_files.find({}, {"url": 1}):
            tracked_urls.add(audio["url"])
        
        # Find orphans
        orphaned = []
        for s3_file in s3_files:
            s3_url = s3_service.get_public_url(s3_file["key"])
            if s3_url not in tracked_urls:
                orphaned.append({
                    "url": s3_url,
                    "s3_key": s3_file["key"],
                    "size": s3_file.get("size", 0),
                    "last_modified": s3_file.get("last_modified")
                })
        
        logger.info(f"🔍 Found {len(orphaned)} orphaned S3 files")
        
        return orphaned
        
    except Exception as e:
        logger.error(f"❌ Orphan scan failed: {e}")
        raise


# Convenience function to run all maintenance tasks
async def run_audio_maintenance(
    cleanup: bool = True,
    grace_period_days: int = 30,
    verify: bool = True,
    retry: bool = True,
    dry_run: bool = False
):
    """
    Run all audio maintenance tasks
    
    Args:
        cleanup: Run cleanup of old unreferenced files
        grace_period_days: Grace period for cleanup
        verify: Run reference count verification
        retry: Retry pending deletions
        dry_run: Don't actually delete anything
    
    Returns:
        dict: Combined statistics from all operations
    """
    results = {}
    
    if verify:
        logger.info("=" * 60)
        logger.info("Running reference count verification...")
        logger.info("=" * 60)
        results["verification"] = await verify_reference_counts()
    
    if retry:
        logger.info("=" * 60)
        logger.info("Retrying pending deletions...")
        logger.info("=" * 60)
        results["retry"] = await retry_pending_deletions()
    
    if cleanup:
        logger.info("=" * 60)
        logger.info(f"Running cleanup (grace period: {grace_period_days} days)...")
        logger.info("=" * 60)
        results["cleanup"] = await cleanup_unreferenced_audio(
            grace_period_days=grace_period_days,
            dry_run=dry_run
        )
    
    return results


if __name__ == "__main__":
    import asyncio
    import argparse
    
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    parser = argparse.ArgumentParser(description="Audio cleanup and maintenance")
    parser.add_argument("--dry-run", action="store_true", help="Don't actually delete anything")
    parser.add_argument("--grace-days", type=int, default=30, help="Grace period in days")
    parser.add_argument("--skip-cleanup", action="store_true", help="Skip cleanup")
    parser.add_argument("--skip-verify", action="store_true", help="Skip verification")
    parser.add_argument("--skip-retry", action="store_true", help="Skip retry")
    
    args = parser.parse_args()
    
    asyncio.run(run_audio_maintenance(
        cleanup=not args.skip_cleanup,
        grace_period_days=args.grace_days,
        verify=not args.skip_verify,
        retry=not args.skip_retry,
        dry_run=args.dry_run
    ))

